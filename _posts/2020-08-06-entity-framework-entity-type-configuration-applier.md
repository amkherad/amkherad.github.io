---
title: Entity Framework - Automatic EntityTypeConfiguration Registration
description: Automatically register all IEntityTypeConfiguration classes in an assembly using expression trees, with optional per-DbContext filtering.
tags: ["entity-framework", "entity-type-configuration", "multi-context", "db-context"]
categories: [DotNET, Entity Framework]
---

Entity Framework Core encourages organizing fluent API mappings in dedicated classes that implement `IEntityTypeConfiguration<TEntity>`. That scales well, but every new configuration must be wired up manually with `modelBuilder.ApplyConfiguration(...)`. In a growing codebase—and especially when you maintain multiple `DbContext` types—that becomes easy to forget.

This post shows a small helper that discovers and applies configurations at runtime, caches the result, and optionally filters which configurations belong to which context.

<!--more-->

## Why automate registration?

Two common motivations:

1. **Less boilerplate** — You add a new `IEntityTypeConfiguration<T>` class and it is picked up automatically; no edits to `OnModelCreating` required.
2. **Multiple contexts** — You can keep a slim runtime `DbContext` for application code and a separate migration context (or other specialized contexts) without duplicating registration logic. That can reduce work during `DbContext` creation when the runtime context only needs a subset of mappings.

Reflection is a reasonable tool here. EF Core already does significant work when building the model, so the one-time cost of scanning an assembly is usually negligible—especially if you compile and cache the applier delegate, as shown below.

## The applier

The helper builds an `Action<ModelBuilder>` once, then reuses it on every `OnModelCreating` call:

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

### How it works

`CreateAutoApplier` takes a `DbContext` type, scans its assembly for classes implementing `IEntityTypeConfiguration<>`, and emits a compiled delegate that calls `ApplyConfiguration` for each one.

Expression trees are used instead of a simple reflection loop so the delegate is compiled once and invoked cheaply afterward. A plain `foreach` with `Activator.CreateInstance` would also work; compiling expressions avoids repeated reflection on every model build when the delegate is not cached.

## Filtering configurations per context

When several contexts share an assembly, not every configuration should apply to every context. An attribute keeps that explicit:

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

Filter the discovered types before building expressions:

```csharp
configurations = configurations
    .Where(t => t.GetCustomAttributes<ApplyOnContextAttribute>()
        .Any(a => a.TargetContext == targetContextType))
    .ToArray();
```

Example configuration shared across runtime and migration contexts:

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

## Wiring it into DbContext

Cache the compiled delegate in a `static readonly` field so discovery and compilation happen only once per application domain:

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

## Summary

- Put fluent mappings in `IEntityTypeConfiguration<T>` classes as usual.
- Let `EntityConfigurationsApplier` discover and apply them, with optional `[ApplyOnContext]` filtering.
- Compile and cache the delegate so registration cost is paid once.

This pattern has served me well on multi-context EF Core projects where manual `ApplyConfiguration` calls were becoming a maintenance burden.
