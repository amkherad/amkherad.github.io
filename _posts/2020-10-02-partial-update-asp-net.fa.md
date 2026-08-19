---
title: به‌روزرسانی جزئی در ASP.NET
description: پیاده‌سازی PATCH در ASP.NET Core با ردیابی propertyهای ارسال‌شده در JSON و یکپارچه‌سازی AutoMapper.
lang: fa
translation_key: partial-update-asp-net
permalink: /fa/posts/partial-update-asp-net/
categories: [DotNET, ASP.net]
tags: [partial-update]
---

APIهای REST معمولاً `PUT` را برای جایگزینی کامل و `PATCH` را برای به‌روزرسانی جزئی expose می‌کنند. با `PUT`، کلاینت باید کل state منبع را بفرستد — حتی برای تغییر یک فیلد. این کار یک read اضافه می‌طلبد، payload را بزرگ می‌کند و evolution API را سخت می‌کند: فیلد required جدید روی سرور می‌تواند کلاینت‌های قدیمی را بشکند تا نسخه جدید API را adopt کنند.

endpoint به‌روزرسانی جزئی به کلاینت اجازه می‌دهد فقط فیلدهایی را بفرستد که می‌خواهد تغییر کند. سرور همچنان read–modify–write داخلی انجام می‌دهد (برای storage پایدار راه دیگری نیست)، اما contract کوچک‌تر و resilient‌تر می‌شود.

این نوشته یک پیاده‌سازی عملی `PATCH` برای ASP.NET Core با `System.Text.Json` — شامل پشتیبانی AutoMapper — را مرحله‌به‌مرحله نشان می‌دهد.

<!--more-->

## به‌روزرسانی کامل و مشکلات آن

الگوی کلاسیک update سمت کلاینت:

```csharp
var value = Read();
value++;
Write(value);
```

مشکلات الزام representation کامل:

- **Round trip اضافه** — کلاینت باید قبل از `PUT` حتماً `GET` بزند، حتی برای یک property.
- **Lost update** — دو کلاینت یک نسخه را می‌خوانند، فیلدهای مختلف را عوض می‌کنند؛ آخرین write برنده می‌شود و تغییر دیگر silently از بین می‌رود.
- **Contract شکننده** — اضافه یا rename کردن property روی سرور می‌تواند کلاینت‌هایی را بشکند که همیشه باید object کامل بفرستند.

به‌روزرسانی جزئی read–modify–write را از بین نمی‌برد؛ آن را پشت سطح API باریک‌تری می‌برد. برای semantics جایگزینی اجباری، `PUT` با optimistic concurrency هنوز ابزار درست است.

> **نکته:** اگر فقط به فرمت استاندارد library-supported نیاز دارید، [JSON Patch (RFC 6902)](https://datatracker.ietf.org/doc/html/rfc6902) با `Microsoft.AspNetCore.JsonPatch` را در نظر بگیرید. رویکرد زیر وقتی مفید است که body JSON ساده (`{ "name": "Ali" }`) می‌خواهید و کنترل صریح روی propertyهای present در request لازم است.

## همزمانی (Concurrency)

در محیط‌های concurrent، updateها را با concurrency token (ETag، row version و مشابه) برای [optimistic concurrency control](https://en.wikipedia.org/wiki/Optimistic_concurrency_control) جفت کنید. flow به‌روزرسانی جزئی مثل full update است: entity را با token بخوانید، تغییرات را اعمال کنید، اگر token دیگر match نکرد write را fail کنید. مکانیزم DTO و property-tracking این نوشته مستقل از نحوه ذخیره و validate کردن token است.

## نمای کلی پیاده‌سازی

در full update، model binding یک DTO کامل می‌دهد. در partial update، لایه service باید بداند **کدام** propertyها در payload JSON آمده‌اند — نه فقط value آن‌ها (property missing با `null` صریح فرق دارد، و فقط فیلدهای ارسال‌شده باید اعمال شوند).

الگو:

1. body را در `PartialUpdateDto<T>` deserialize کنید.
2. نام propertyها را از JSON خام ثبت کنید.
3. فقط همان propertyها را روی entity ذخیره‌شده اعمال کنید.

### PartialUpdateDto

```csharp
public class PartialUpdateDto<T>
{
    public T Model { get; set; }

    public HashSet<string> Properties { get; set; }
}
```

actionهای controller به‌جای `TCrudDto` مستقیم، `PartialUpdateDto<TCrudDto>` می‌گیرند.

### PartialUpdateDtoJsonConverter

`System.Text.Json` بعد از deserialization نمی‌گوید کدام propertyها در payload بودند. یک converter سفارشی نام propertyها را هنگام ساخت model ثبت می‌کند. استفاده از `JsonDocument` وابستگی به APIهای internal `Utf8JsonReader` را حذف می‌کند:

```csharp
using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

public class PartialUpdateDtoJsonConverter<T> : JsonConverter<PartialUpdateDto<T>>
{
    public override PartialUpdateDto<T> Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        var properties = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var property in document.RootElement.EnumerateObject())
        {
            properties.Add(property.Name);
        }

        var model = document.RootElement.Deserialize<T>(options);

        return new PartialUpdateDto<T>
        {
            Model = model,
            Properties = properties
        };
    }

    public override void Write(
        Utf8JsonWriter writer,
        PartialUpdateDto<T> value,
        JsonSerializerOptions options)
    {
        JsonSerializer.Serialize(writer, value.Model, options);
    }
}
```

converter را برای هر DTO type استفاده‌شده در actionهای partial-update ثبت کنید (پایین‌تر).

### RegisterPartialUpdateDto

controllerها را برای parameterهای `PartialUpdateDto<>` اسکن کنید و converterها را خودکار ثبت کنید:

```csharp
using System;
using System.Linq;
using System.Reflection;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Mvc;

public static class PartialUpdateDtoRegistration
{
    public static void RegisterPartialUpdateDto(
        JsonSerializerOptions options,
        Assembly assembly)
    {
        var dtoTypes = assembly.GetTypes()
            .Where(t => t.GetCustomAttributes().Any(a => a is ApiControllerAttribute))
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Instance))
            .SelectMany(m => m.GetParameters())
            .Select(p => p.ParameterType)
            .Where(t => t.IsGenericType &&
                        t.GetGenericTypeDefinition() == typeof(PartialUpdateDto<>))
            .Select(t => t.GetGenericArguments()[0])
            .Distinct();

        foreach (var dtoType in dtoTypes)
        {
            var converterType = typeof(PartialUpdateDtoJsonConverter<>).MakeGenericType(dtoType);
            if (Activator.CreateInstance(converterType) is JsonConverter converter)
            {
                options.Converters.Add(converter);
            }
        }
    }
}
```

در `Program.cs` / `Startup.ConfigureServices`:

```csharp
services.AddControllers()
    .AddJsonOptions(options =>
    {
        PartialUpdateDtoRegistration.RegisterPartialUpdateDto(
            options.JsonSerializerOptions,
            typeof(Startup).Assembly);
    });
```

### Controller

```csharp
[HttpPatch("{publicId}")]
public virtual async Task<BaseResponseDto<TCrudDto>> UpdatePartialAsync(
    [FromRoute][Required] int publicId,
    [FromBody] PartialUpdateDto<TCrudDto> values,
    CancellationToken cancellationToken)
{
    return await CrudService.PartialUpdateAsync(
        publicId,
        values.Properties,
        values.Model,
        cancellationToken);
}
```

برای partial update از HTTP verb `PATCH` استفاده کنید.

### CRUD service (نگاشت مستقیم property)

وقتی نام propertyهای DTO و entity یکی است:

```csharp
public virtual async Task<TEntity> PartialUpdateAsync(
    TPublicKey publicId,
    HashSet<string> updatedProperties,
    TEntity updatedValues,
    CancellationToken cancellationToken)
{
    var entity = await Repository.GetByPublicId(publicId, cancellationToken);

    if (entity is null)
    {
        throw new EntityNotFoundException(typeof(TEntity).Name, publicId);
    }

    if (!updatedProperties.Any())
    {
        return entity;
    }

    var properties = typeof(TEntity)
        .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.SetProperty)
        .ToDictionary(p => p.Name, p => p, StringComparer.OrdinalIgnoreCase);

    var hasChanges = false;

    foreach (var propertyName in updatedProperties)
    {
        if (!properties.TryGetValue(propertyName, out var property))
        {
            continue;
        }

        var oldValue = property.GetValue(entity);
        var newValue = property.GetValue(updatedValues);

        if (Equals(oldValue, newValue))
        {
            continue;
        }

        hasChanges = true;
        property.SetValue(entity, newValue);
    }

    if (hasChanges)
    {
        await Repository.Update(entity, cancellationToken);
        await UnitOfWork.SaveChangesAsync(cancellationToken);
    }

    return entity;
}
```

عمداً ساده است. در production ممکن است mapping library، setterهای type-safe یا validation rule به‌جای reflection خام ترجیح داده شود.

### CRUD service مبتنی بر mapper (AutoMapper)

وقتی نام DTO و entity فرق دارد، mapping را از AutoMapper بگیرید:

```csharp
public virtual async Task<TCrudDto> PartialUpdateAsync(
    TPublicKey publicId,
    HashSet<string> updatedProperties,
    TCrudDto updatedValues,
    CancellationToken cancellationToken)
{
    var entity = await Repository.GetByPublicId(publicId, cancellationToken);

    if (entity is null)
    {
        throw new EntityNotFoundException(typeof(TEntity).Name, publicId);
    }

    if (!updatedProperties.Any())
    {
        return Mapper.Map<TCrudDto>(entity);
    }

    var entityProperties = typeof(TEntity)
        .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.SetProperty)
        .ToDictionary(p => p.Name, p => p);

    var typeMap = Mapper.ConfigurationProvider.FindTypeMapFor(typeof(TCrudDto), typeof(TEntity));
    var propertyMaps = typeMap.MemberMaps
        .Where(m => m.SourceMember != null)
        .ToDictionary(
            m => m.SourceMember.Name,
            m => m.DestinationName,
            StringComparer.OrdinalIgnoreCase);

    var updateTarget = Mapper.Map<TEntity>(updatedValues);
    var hasChanges = false;

    foreach (var dtoPropertyName in updatedProperties)
    {
        if (!propertyMaps.TryGetValue(dtoPropertyName, out var entityPropertyName))
        {
            continue;
        }

        if (!entityProperties.TryGetValue(entityPropertyName, out var property))
        {
            continue;
        }

        var oldValue = property.GetValue(entity);
        var newValue = property.GetValue(updateTarget);

        if (Equals(oldValue, newValue))
        {
            continue;
        }

        hasChanges = true;
        property.SetValue(entity, newValue);
    }

    if (hasChanges)
    {
        await Repository.Update(entity, cancellationToken);
        await UnitOfWork.SaveChangesAsync(cancellationToken);
    }

    return Mapper.Map<TCrudDto>(entity);
}
```

برای modelهای سطحی خوب کار می‌کند. objectهای تو در تو، collectionها و گراف relation به merge ruleهای domain-specific نیاز دارند که یک helper generic پوشش نمی‌دهد.

## جمع‌بندی

- به‌روزرسانی جزئی contract API را باریک می‌کند؛ سرور همچنان storage را می‌خواند و می‌نویسد.
- `PartialUpdateDto<T>` به‌همراه JSON converter، **value**ها را از **فیلدهای ارسال‌شده** جدا می‌کند.
- converterها را یک‌بار ثبت کنید، endpointهای `PATCH` expose کنید و فقط propertyهای لیست‌شده را — با mapping مستقیم یا AutoMapper — اعمال کنید.
- برای editهای concurrent امن، با concurrency token ترکیب کنید؛ وقتی فرمت patch استاندارد کافی است JSON Patch را در نظر بگیرید.
