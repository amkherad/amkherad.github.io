---
title: Distributed lock implementation
categories: ["Distributed Systems"]
excerpt_separator: __MORE__
---

![Cyber Lock Image](/assets/img/content/2020-08-07-distributed-lock/lock.jpg)

In this article we're going to implement a highly available distributed lock so we can lock in multiple horizontally scaled
application servers. __MORE__

## The Problem
Consider you want to make an online stock exchange application where many clients would connect to your servers,
and they want to buy or sell stocks as they like, and you've been lucky that your application is the main stream application
for doing so, Thus there are millions of clients connecting to your servers and having their daily exchange.
Obviously you can't handle that much clients just by a single server so you may want to add multiple servers or event multiple
clusters of multiple servers to serve the clients.

Something like stock exchange must be thread-safe to prevent selling the same unit to multiple people, so the simplest way is
to have exclusive locks when you want to register a transaction on a specific stock. Having multiple servers prevents you to have
a simple in process (or OS-wide) locks.

## The Answer
So you may want to implement critical code on a single machine and make other servers to forward
their requests to this single server, by doing that you're making a single point of failure, Thus when this single server goes
down, every other dependent server will go down and they can't serve until this single server is ressurected or is replaced with
another server.

Another approach is to have all servers work independently, but when they want to lock something, they ask a remote server
(the coordinator) to allow them do their job and prevent others to work on the same thing concurrently. This is acctually a
good solution but it has it's drawbacks. For instance this is still a single point of failure, but in most cases it doesn't matter
and it's acceptable for the servers to have downtime for a little time.

But if you want to eliminate every chance of failure or at least make it so little you can implement a disctributed lock manager (DLM)
and use it to lock more reliably in multiple cluster servers.

## Using Redis For Lock Implementation
The minimum thing we require to implement a simple exclusive lock everywhere is
[Compare-and-swap](https://en.wikipedia.org/wiki/Compare-and-swap) (aka compare-exchange)