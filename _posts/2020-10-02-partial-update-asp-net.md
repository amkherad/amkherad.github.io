---
title: Partial update in ASP.net
categories: [DotNET, ASP.net]
tags: partial-update
---

In this article we're going to implement a partial-update mechanism for our CRUD APIs so we could benefit from its merits.
<!--more-->


## What is update and what are it's drawbacks?
Before we begin, we better understand what partial update is and what advantages it has.  
Well, lets begin by explaining how we should update without partial update. To update data, we have to fetch it first, and then we could alter it (e.g. increment), and finally we may want to replace old value with the new value:
```csharp
var value1 = read();
value1 ++;
write(value1);
```
This classical approach has many downsides such as:
* Every client (user) has to provide a full state of the object for the update endpoint, meaning they all have to read the data before updating.
* It is not thread-safe, which means, during the altering phase other clients might update the data, so state of the data is no longer valid and clients may not see the latest state of data/objects.
* Subsequent changes to structure of the data may break the clients, and they have to update their models to use new API versions. Because the update requires a full state of data. This will lead to many API versions with a small change to their model.

There is no magic bullet to avoid these three phases (read, modify, write), so these problems always exist, but we could bring them closer to each other and instead of forcing client to read-modify-write, the server (the update endpoint) takes the responsibility to handle these three phases, specially bearing in mind, server MUST perform such operations one way or another to check for data integrity (i.e. concurrency/fencing tokens).
N.B. This is only a remedy for situations where we want to allow force-replacing the data, using partial update for this purpose is not thread-safe, so it's not recommended.

Also, the main problem (i.e. clients have to provide a full state of the data) could be eliminated if we allow clients to provide only the portion of the data they want to modify.


## Concurrency
In concurrent systems where parallel updates could cause problems, we could take them out by providing a concurrency token, which considered an [optimistic concurrency control](https://en.wikipedia.org/wiki/Optimistic_concurrency_control). Likewise in partial update we could provide a concurrency token to prevent parallel updates optimistically.


## Implementation
In case of full-update when we have the entire object, we could fill a model with the given values and pass it to the repository or whatever you're using for updates.
But in case of partial-update, mechanism for handling partial-update in lower levels should receive information about fields and their value to update, we couldn't just pass the model, because not all the fields have been updated.

### PartialUpdateDto
To implement partial-update in ASP.net I'm of the opinion that we need a model to contain the DTO and a list of the properties which have been updated.
```csharp
public class PartialUpdateDto<T>
{
    public T Model { get; set; }

    public HashSet<string> Properties { get; set; }
}
```
Then we could simply take this model instead of the update/command model itself, and with a little configuration we could have the model and updated properties.

### PartialUpdateDtoJsonConverter
The configuration could vary depending on the libraries you're using. For me, I'm using `System.Text.Json` for serialization, so to allow mapping to this model we need a custom `JsonConverter`, I use the following code, but it depends on internal implementation so be carefull about using it.
```csharp
//A delegate type to provide access to internal span in an `Utf8JsonReader` type.
internal delegate ReadOnlySpan<byte> Utf8JsonReaderSpanAccessorDelegate(
    Utf8JsonReader reader
);

public class PartialUpdateDtoJsonConverter<T> : JsonConverter<PartialUpdateDto<T>>
{
    //A function to provide access to internal span in an `Utf8JsonReader` type.
    private static readonly Utf8JsonReaderSpanAccessorDelegate OriginalSpanAccessor;

    //Static constructor to initialize the OriginalSpanAccessor.
    //This method is unsafe, and I will replace it with a better implementation ASAP.
    static PartialUpdateDtoJsonConverter()
    {
        var property = typeof(Utf8JsonReader)
            .GetProperty("OriginalSpan", BindingFlags.GetProperty | BindingFlags.NonPublic |
                BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);

        var param = Expression.Parameter(typeof(Utf8JsonReader));
        var memberAccess = Expression.Property(param, property);

        var lambda = Expression.Lambda<Utf8JsonReaderSpanAccessorDelegate>(memberAccess, param);

        OriginalSpanAccessor = lambda.Compile();
    }


    public override PartialUpdateDto<T> Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options
    )
    {
        var span = OriginalSpanAccessor(reader);

        var originalBytes = span;

        var fields = new HashSet<string>();
        var jObj = new Utf8JsonReader(originalBytes);

        var obj = JsonSerializer.Deserialize<T>(ref reader, options);

        while (jObj.Read())
        {
            if (jObj.CurrentDepth == 1 && jObj.TokenType == JsonTokenType.PropertyName)
            {
                fields.Add(Encoding.UTF8.GetString(jObj.ValueSpan));
            }
        }

        return  new PartialUpdateDto<T>
        {
            Model = obj,
            Fields = fields
        };
    }

    public override void Write(
        Utf8JsonWriter writer,
        PartialUpdateDto<T> value,
        JsonSerializerOptions options
    )
    {
        throw new NotImplementedException();
    }
}
```
After adding this class we need to register each model that is wrapped with `PartialUpdateDto`, in `JsonSerializerOptions`.

### RegisterPartialUpdateDto
This method could be usefull, but it's up to you and your softwares' structure to find the most suitable way to register them.

```csharp
public void RegisterPartialUpdateDto(
    JsonSerializerOptions opt,
    Assembly assembly
)
{
    var baseControllerType = typeof(ControllerBase);

    // This function finds a PartialUpdateDto<XX> in type hierarchy or returns null.
    Type GetPartialUpdateDto(
        Type t
    )
    {
        var that = t;

        do {
            if (!that.IsGenericType)
            {
                continue;
            }

            if (typeof(PartialUpdateDto<>) == that.GetGenericTypeDefinition())
            {
                return that;
            }
            
        } while ((that = that.BaseType) != null);

        return null;
    }

    var partialUpdateDtoList = assembly.GetTypes()
        .Where(t => !t.IsGenericType && typeof(ControllerBase).IsAssignableFrom(t))
        .SelectMany(t =>
        {
            return t
                .GetMethods(BindingFlags.Public | BindingFlags.Instance)
                .Select(m => m.GetParameters())
                .Where(p => !(p is null) && p.Any())
                .SelectMany(p => p)
                .Select(p => GetPartialUpdateDto(p))
                .Where(p => !(p is null))
                .Select(p => 
                    typeof(PartialUpdateDtoJsonConverter<>)
                        .MakeGenericType(p)
                )
            ;
        }).ToArray();

    foreach (var converterType in partialUpdateDtoList)
    {
        var instance = Activator.CreateInstance(converterType);
        if (instance is JsonConverter jsonConverter)
        {
            opt.Converters.Add(jsonConverter);
        }
    }
}
```

Then we should call this method and apply it's changes on a `JsonSerializerOptions` in our `ConfigureServices` method.

```csharp
services.AddControllers() //It's in your Startup.ConfigureServices method
    .AddJsonOptions(opt =>
    {
        RegisterPartialUpdateDto(opt.JsonSerializerOptions, typeof(Startup).Assembly);
    });
```

### Controller

After doing so, we are able to use `PartialUpdateDto<>` as our input models in controller actions.
```csharp
[HttpPatch("{publicId}")]
public virtual async Task<BaseResponseDto<TCrudDto>> UpdatePartialAsync(
    [FromRoute] [Required] int publicId,
    [FromBody] PartialUpdateDto<TCrudDto> values,
    CancellationToken cancellationToken
)
{
    return await CrudService.PartialUpdateAsync(
        publicId, values.Properties, values.Model, cancellationToken);
    // Or you could pass down (e.g. dispatch) the PartialUpdateDto itself.
}
```
* Conventional HTTP verb for partial-update is patch.

### CRUD Service

Now the CRUD service has both the model and a list of updated properties. You can simply write your own partial-update method like below.
```csharp
public virtual async Task<TEntity> PartialUpdateAsync(
    TPublicKey publicId,
    HashSet<string> updatedProperties,
    TEntity updatedValues,
    CancellationToken cancellationToken
)
{
    var entity = await Repository.GetByPublicId(publicId, cancellationToken);

    if (entity is null)
    {
        throw new EntityNotFoundException(typeof(TEntity).Name, publicId);
    }

    if (updatedProperties.Any())
    {
        var properties = typeof(TEntity)
            .GetProperties(
                BindingFlags.Public |
                BindingFlags.SetProperty |
                BindingFlags.Instance
            )
            .ToDictionary(k => k.Name.ToLower(), v => v);

        var hasChange = false;

        foreach (var value in updatedProperties)
        {
            if (properties.TryGetValue(value, out var property)) {
                var oldValue = property.GetValue(entity);
                var newValue = property.GetValue(updateTarget);

                if (Object.Equals(oldValue, newValue))
                {
                    continue;
                }

                hasChange = true;

                //entity.Property = (TProperty) updatedEntity.Property
                property.SetValue(
                    entity,
                    Convert.ChangeType(
                        newValue,
                        property.PropertyType
                    )
                );
            }
        }

        if (hasChange)
        {
            await Repository.Update(entity, cancellationToken);

            await UnitOfWork.SaveChangesAsync(cancellationToken);
        }
    }

    return entity;
}
```
This code handles partial-update very simply but it has some problems:  
* What if we're using a mapper to map a DTO to our database models?
* Also property.SetValue and Convert.ChangeType are so primitive and may cause problems.

### Mapper-based CRUD service

If you're using a mapper, it could get complicated, because you have to integerate with your mapper to get name mappings. For this example I'm going to use `AutoMapper` to implement the mapper-based solution.

```csharp
public virtual async Task<TCrudDto> PartialUpdateAsync(
    TPublicKey publicId,
    HashSet<string> updatedProperties,
    TCrudDto updatedValues,
    CancellationToken cancellationToken
)
{
    var entity = await Repository.GetByPublicId(publicId, cancellationToken);

    if (entity is null)
    {
        throw new EntityNotFoundException(typeof(TEntity).Name, publicId);
    }

    if (updatedProperties.Any())
    {
        var properties = typeof(TEntity)
            .GetProperties(BindingFlags.Public | BindingFlags.SetProperty | BindingFlags.Instance)
            .ToDictionary(k => k.Name, v => v);

        var typeMap = Mapper.ConfigurationProvider.FindTypeMapFor(
            typeof(TCrudDto), typeof(TEntity));

        var propertyMaps = typeMap.MemberMaps.ToDictionary(
            k => k.SourceMember?.Name?.ToLower(),
            v => v.DestinationName
        );

        var updateTarget = Mapper.Map<TEntity>(updatedValues);

        var hasChanged = false;

        foreach (var value in updatedProperties)
        {
            if (propertyMaps.TryGetValue(value.ToLower(), out var propertyName))
            {
                if (properties.TryGetValue(propertyName, out var property))
                {
                    var oldValue = property.GetValue(entity);
                    var newValue = property.GetValue(updateTarget);

                    if (Object.Equals(oldValue, newValue))
                    {
                        continue;
                    }

                    hasChanged = true;

                    //entity.Property = updatedEntity.Property
                    property.SetValue(
                        entity,
                        Convert.ChangeType(
                            newValue,
                            property.PropertyType
                        )
                    );
                }
            }
        }

        if (hasChanged)
        {
            await Repository.Update(entity, cancellationToken);

            await UnitOfWork.SaveChangesAsync(cancellationToken);
        }
    }

    return Mapper.Map<TCrudDto>(entity);
}
```

This implementation should be enough for simple shallow models, but for complex, relation-based models, it's not satisfying, and you have to implement a complex CRUD service, which is out of the scope of this article, but you could implement your own.
