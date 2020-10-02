---
title: Partial update in ASP.net
categories: [DotNET, ASP.net]
tags: partial-update
---

In this article we're going to implement a partial-update mechanism for our CRUD APIs so we could benefit from its merits.
<!--more-->

* the problems
* how to implement

## What is update and what are it's drawbacks?
Before we begin, we better understand what partial update is and what advantages it has.  
Well, lets begin by explaining how we should update without partial update. To update a data we have to fetch it first, and then we could alter it, and in the end we may want to replace the old value with the new value:
```csharp
    var oldValue = fetch();
    oldValue ++;
    writeBack(oldValue);
```
This classical approach has many downsides such as:
* Every client (user) has to provide a full state of the object for the update endpoint, so they all have to read the data before updating.
* It is not thread-safe, meaning during the altering phase other clients might update the data, so the state of the data is no longer valid, and clients may not see the latest state of data/objects.
* Subsequent changes to structure of the data may break the clients they have to update their models to use new API versions, because the update requires a `full` state of the object. This will lead to many API versions with a small change to their model.

There is not a magic bullet to avoid these three phases (read, modify, write), so these problems always exist, but we could bring them closer to each other which means, instead of forcing client to read-modify-write, the server (the update endpoint) takes the responsibility to handle these three phases, specially bearing in mind, server MUST perform such operation one way or another to check for data integrity (i.e. concurrency/fencing tokens).
N.B. This is only a remedy for situations where we want to force-replace the data, and using partial update like this is not thread-safe, so it's not recommended.

Also, the main problem (i.e. clients have to provide a full state of the data) could be eliminated if we allow clients to provide only the portion of the data they want to modify.

## Concurrency
