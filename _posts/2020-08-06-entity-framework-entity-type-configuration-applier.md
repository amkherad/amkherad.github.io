---
title: Entity Framework - Automatic EntityTypeConfiguration registeration
tags: entity-framework automatically register entity-type-configuration multi-context multiple db-context
categories: [DotNET, Entity Framework]
---

In this article I'm going to create a simple helper class to automatically register all EntityTypeConfigurations in an assembly.
<!-- more -->

One way to organize entity framework's fluent configurations would be to put them in separate class that implements
the `IEntityTypeConfiguration<TEntity>` interface. But with a growing application remembering to apply new configurations
using `ApplyConfiguration` method in `ModelBuilder` class can be challenging.

Another usage would be when you want to separate
your migration context from other contexts that are used throughout your application (it's usefull to increase the performance for DbContext creation).

You can using reflection to register the configuration without having to worry about performance, because EF already does a lot when it's making a new instance of DbContext so adding a little reflection penalty is nothing.

---

I'm always using this class:
```csharp
public class EntityConfigurationsApplier
{
    public static Action<ModelBuilder> CreateAutoApplier(
        Type targetContextType
    )
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
            .FirstOrDefault(m =>
                m.Name == nameof(ModelBuilder.ApplyConfiguration));

        if (applyConfigMethod is null)
        {
            throw new InvalidOperationException();
        }

        var modelBuilderParameter = Expression.Parameter(typeof(ModelBuilder), "modelBuilder");

        var commands = new List<Expression>();

        foreach (var config in configurations)
        {
            var entityType = config.GetInterfaces()
                .Single(
                    i => i.IsGenericType &&
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

The `CreateAutoApplier` method creates a delegate that takes a `ModelBuilder` as it's parameter and calls all the desired entity configurations against it.
The strategy for the creator is that it takes a context type as an input parameter, then it gets the assembly of the context type,
and in that assembly it lists all types which implements `IEntityTypeConfiguration<>` interface.

You can also filter configurations as you like, you just need to add your extra filters to the `configurations` variable. For example I always
create an attribute class called `ApplyOnContextAttribute` that takes a type as it's parameter to determine which context(s) the configuration
should be applied to.

```csharp
[AttributeUsage(AttributeTargets.Class, AllowMultiple = true)]
public class ApplyOnContextAttribute : Attribute
{
    public Type TargetContext { get; }
    
    public ApplyOnContextAttribute(
        Type targetContext
    )
    {
        TargetContext = targetContext;
    }
}
```

And right after the line which `configurations` is defined, I put these codes:

```csharp
configurations = configurations
    .Where(t =>
    {
        var attributes = t.GetCustomAttributes();

        var context = attributes
            .FirstOrDefault(a =>
                a is ApplyOnContextAttribute applyOnContext &&
                applyOnContext.TargetContext == targetContextType
            );

        return !(context is null);
    })
    .ToArray();
```

Then you can use it like this:

```csharp
//The context which contains DbSet<IdentityUserEntity> for use in code.
[ApplyOnContext(typeof(DataContext))]
//The context that's used for migrations.
[ApplyOnContext(typeof(MigrationContext))]
public class IdentityUserEntityConfiguration : IEntityTypeConfiguration<IdentityUserEntity>
{
    public void Configure(
        EntityTypeBuilder<IdentityUserEntity> builder
    )
    {
        //
    }
}
```

Finally when you want to apply an entity configuration to a context you can use this code:

```csharp
public class DataContext : DbContext {
    private static readonly Lazy<Action<ModelBuilder>> EntityConfigurationApplierInstance =
            new Lazy<Action<ModelBuilder>>(
                () => EntityConfigurationsApplier.CreateAutoApplier(typeof(DataContext))
            );

    protected override void OnModelCreating(
        ModelBuilder modelBuilder
    )
    {
        base.OnModelCreating(modelBuilder);

        EntityConfigurationApplierInstance.Value.Invoke(modelBuilder);
    }
}
```

It creates the delegate for registration and caches it for future uses.