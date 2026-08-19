---
title: Partial Update in ASP.NET
description: Implement PATCH-style partial updates in ASP.NET Core by tracking which JSON properties were sent, with AutoMapper integration.
categories: [DotNET, ASP.net]
tags: [partial-update]
---

REST APIs often expose `PUT` for full replacement and `PATCH` for partial updates. With `PUT`, clients must send the entire resource state—even for a one-field change. That forces an extra read, increases payload size, and makes API evolution painful: a new required field on the server can break older clients until they adopt a new API version.

A partial-update endpoint lets clients send only the fields they want to change. The server still performs read–modify–write internally (there is no way around that for durable storage), but the contract becomes smaller and more resilient.

This post walks through a practical `PATCH` implementation for ASP.NET Core using `System.Text.Json`, including AutoMapper support.

<!--more-->

## Full update and its drawbacks

The classic client-driven update looks like this:

```csharp
var value = Read();
value++;
Write(value);
```

Problems with requiring a full resource representation:

- **Extra round trip** — Clients must `GET` before `PUT`, even to change one property.
- **Lost updates** — Two clients can read the same version, modify different fields, and whichever writes last wins; the other change is silently overwritten.
- **Brittle contracts** — Adding or renaming server-side properties can break clients that must always send a complete object.

Partial update does not remove read–modify–write on the server; it moves that work behind a narrower API surface. For force-replace semantics, `PUT` with optimistic concurrency is still the right tool.

> **Note:** If you only need a standard, library-supported format, consider [JSON Patch (RFC 6902)](https://datatracker.ietf.org/doc/html/rfc6902) via `Microsoft.AspNetCore.JsonPatch`. The approach below is useful when you want plain JSON bodies (`{ "name": "Ali" }`) and explicit control over which properties were present in the request.

## Concurrency

In concurrent environments, pair updates with a concurrency token (ETag, row version, or similar) for [optimistic concurrency control](https://en.wikipedia.org/wiki/Optimistic_concurrency_control). The partial-update flow is the same as for full updates: read the entity including its token, apply changes, and fail the write if the token no longer matches. The DTO and property-tracking mechanics in this post are independent of how you store and validate that token.

## Implementation overview

For a full update, model binding gives you a complete DTO. For partial update, the service layer also needs to know **which** properties appeared in the JSON payload—not just their values (a missing property and an explicit `null` are different concerns, and only sent fields should be applied).

The pattern:

1. Deserialize the body into `PartialUpdateDto<T>`.
2. Track property names from the raw JSON.
3. Apply only those properties to the persisted entity.

### PartialUpdateDto

```csharp
public class PartialUpdateDto<T>
{
    public T Model { get; set; }

    public HashSet<string> Properties { get; set; }
}
```

Controller actions accept `PartialUpdateDto<TCrudDto>` instead of `TCrudDto` directly.

### PartialUpdateDtoJsonConverter

`System.Text.Json` does not tell you which properties were present in the payload after deserialization. A custom converter records property names while building the model. Using `JsonDocument` avoids relying on internal `Utf8JsonReader` APIs:

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

Register the converter for each DTO type used in partial-update actions (see below).

### RegisterPartialUpdateDto

Scan controllers for `PartialUpdateDto<>` parameters and register converters automatically:

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

In `Program.cs` / `Startup.ConfigureServices`:

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

Use `PATCH` as the HTTP verb for partial updates.

### CRUD service (direct property mapping)

When DTO property names match entity property names:

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

This is intentionally simple. Production code may prefer a mapping library, type-safe setters, or validation rules instead of raw reflection.

### Mapper-based CRUD service (AutoMapper)

When DTO and entity names differ, resolve mappings through AutoMapper:

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

This works well for shallow models. Nested objects, collections, and relationship graphs need domain-specific merge rules beyond what a generic helper can provide.

## Summary

- Partial update narrows the API contract; the server still reads and writes storage.
- `PartialUpdateDto<T>` plus a JSON converter separates **values** from **which fields were sent**.
- Register converters once, expose `PATCH` endpoints, and apply only listed properties—through direct mapping or AutoMapper.
- Combine with concurrency tokens for safe concurrent edits, and consider JSON Patch when a standard patch document format is enough.
