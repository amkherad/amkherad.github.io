---
title: Entity Framework - ثبت خودکار EntityTypeConfiguration
description: ثبت خودکار همه کلاس‌های IEntityTypeConfiguration در یک assembly با expression tree و فیلتر اختیاری برای هر DbContext.
lang: fa
translation_key: entity-framework-entity-type-configuration-applier
permalink: /fa/posts/entity-framework-entity-type-configuration-applier/
tags: ["entity-framework", "entity-type-configuration", "multi-context", "db-context"]
categories: [DotNET, Entity Framework]
---

Entity Framework Core نگاشت‌های Fluent API را در کلاس‌های جداگانه‌ای که `IEntityTypeConfiguration<TEntity>` را پیاده‌سازی می‌کنند، پیشنهاد می‌دهد. این رویکرد مقیاس‌پذیر است، اما برای هر configuration جدید باید به‌صورت دستی `modelBuilder.ApplyConfiguration(...)` را فراخوانی کنید. در پروژه‌های بزرگ — و به‌ویژه وقتی چند `DbContext` دارید — فراموش کردن این کار آسان است.

این نوشته یک helper کوچک نشان می‌دهد که configurationها را در runtime پیدا و اعمال می‌کند، نتیجه را cache می‌کند و در صورت نیاز آن‌ها را برای هر context فیلتر می‌کند.

<!--more-->

## چرا ثبت خودکار؟

دو انگیزه رایج:

1. **کمتر boilerplate** — کلاس `IEntityTypeConfiguration<T>` جدید اضافه می‌کنید و خودکار شناسایی می‌شود؛ نیازی به ویرایش `OnModelCreating` نیست.
2. **چند context** — می‌توانید یک `DbContext` سبک برای runtime و یک context جدا برای migration (یا contextهای تخصصی دیگر) داشته باشید، بدون تکرار منطق ثبت. این کار می‌تواند ساخت `DbContext` را سبک‌تر کند وقتی runtime فقط به زیرمجموعه‌ای از mappingها نیاز دارد.

Reflection ابزار مناسبی است. EF Core هنگام ساخت model کار زیادی انجام می‌دهد، بنابراین هزینه یک‌باره scan کردن assembly معمولاً ناچیز است — به‌ویژه اگر delegate را compile و cache کنید، همان‌طور که پایین‌تر آمده.

## Applier

این helper یک‌بار `Action<ModelBuilder>` می‌سازد و در هر فراخوانی `OnModelCreating` از آن استفاده می‌کند:

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using Microsoft.EntityFrameworkCore;

public class EntityConfigurationsApplier
{
    public static Action<ModelBuilder> CreateAutoApplier(Type targetContextType)
    {
        var configurations = targetContextType.Assembly
            .GetTypes()
            .Where(t => t.GetInterfaces()
                .Any(i => i.IsGenericType &&
                          i.GetGenericTypeDefinition() ==
                          typeof(IEntityTypeConfiguration<>)))
            .ToArray();

        var applyConfigMethod = typeof(ModelBuilder)
            .GetMethods(BindingFlags.Public | BindingFlags.Instance)
            .Single(m =>
                m.Name == nameof(ModelBuilder.ApplyConfiguration) &&
                m.IsGenericMethodDefinition);

        var modelBuilderParameter = Expression.Parameter(typeof(ModelBuilder), "modelBuilder");
        var commands = new List<Expression>();

        foreach (var config in configurations)
        {
            var entityType = config.GetInterfaces()
                .Single(i => i.IsGenericType &&
                             i.GetGenericTypeDefinition() ==
                             typeof(IEntityTypeConfiguration<>))
                .GetGenericArguments()
                .Single();

            var target = applyConfigMethod.MakeGenericMethod(entityType);
            var instance = Expression.New(config);
            var call = Expression.Call(modelBuilderParameter, target, instance);

            commands.Add(call);
        }

        var body = Expression.Block(commands);
        var lambda = Expression.Lambda<Action<ModelBuilder>>(body, modelBuilderParameter);

        return lambda.Compile();
    }
}
```

### نحوه کار

`CreateAutoApplier` نوع `DbContext` را می‌گیرد، assembly آن را برای کلاس‌های `IEntityTypeConfiguration<>` اسکن می‌کند و یک delegate کامپایل‌شده می‌سازد که `ApplyConfiguration` را برای هر کدام فراخوانی می‌کند.

به‌جای حلقه reflection ساده از expression tree استفاده شده تا delegate یک‌بار compile شود و بعد ارزان اجرا شود. یک `foreach` با `Activator.CreateInstance` هم کار می‌کند؛ compile کردن expression از reflection مکرر در هر model build — وقتی delegate cache نشده — جلوگیری می‌کند.

## فیلتر configuration برای هر context

وقتی چند context یک assembly را به اشتراک می‌گذارند، هر configuration نباید روی همه contextها اعمال شود. یک attribute این موضوع را شفاف می‌کند:

```csharp
[AttributeUsage(AttributeTargets.Class, AllowMultiple = true)]
public class ApplyOnContextAttribute : Attribute
{
    public Type TargetContext { get; }

    public ApplyOnContextAttribute(Type targetContext)
    {
        TargetContext = targetContext;
    }
}
```

قبل از ساخت expressionها، نوع‌های پیدا شده را فیلتر کنید:

```csharp
configurations = configurations
    .Where(t => t.GetCustomAttributes<ApplyOnContextAttribute>()
        .Any(a => a.TargetContext == targetContextType))
    .ToArray();
```

مثال configuration مشترک بین runtime و migration:

```csharp
[ApplyOnContext(typeof(DataContext))]
[ApplyOnContext(typeof(MigrationContext))]
public class IdentityUserEntityConfiguration
    : IEntityTypeConfiguration<IdentityUserEntity>
{
    public void Configure(EntityTypeBuilder<IdentityUserEntity> builder)
    {
        // mapping rules
    }
}
```

## اتصال به DbContext

delegate کامپایل‌شده را در یک فیلد `static readonly` cache کنید تا discovery و compilation فقط یک‌بار در هر application domain انجام شود:

```csharp
public class DataContext : DbContext
{
    private static readonly Lazy<Action<ModelBuilder>> EntityConfigurationApplier =
        new Lazy<Action<ModelBuilder>>(
            () => EntityConfigurationsApplier.CreateAutoApplier(typeof(DataContext)));

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        EntityConfigurationApplier.Value(modelBuilder);
    }
}
```

## جمع‌بندی

- نگاشت‌های Fluent را مثل همیشه در کلاس‌های `IEntityTypeConfiguration<T>` قرار دهید.
- `EntityConfigurationsApplier` آن‌ها را پیدا و اعمال کند، با فیلتر اختیاری `[ApplyOnContext]`.
- delegate را compile و cache کنید تا هزینه ثبت فقط یک‌بار پرداخت شود.

این الگو در پروژه‌های EF Core چند context که فراخوانی دستی `ApplyConfiguration` دردسر maintenance بود، برای من خوب جواب داده است.
