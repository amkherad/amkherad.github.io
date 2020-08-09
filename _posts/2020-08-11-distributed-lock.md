---
title: Distributed lock implementation
categories: ["Distributed Systems"]
excerpt_separator: <!--more-->
---

![Cyber Lock Image](/assets/img/content/2020-08-07-distributed-lock/lock.jpg)

In this article we're going to implement a highly available distributed lock so we can lock in multiple horizontally scaled
application servers.
<!--more-->


## The Problem
Consider you want to make an online stock exchange application where many clients would connect to your servers,
and they want to buy or sell stocks as they like, and you've been lucky that your application is the main stream application
for doing so, Thus there are millions of clients connecting to your servers and having their daily exchange.
Obviously you can't handle that much clients just by a single server so you may want to add multiple servers or event clusters of nodes to serve the clients.

Something like stock exchange must be thread-safe to prevent selling the same unit to multiple people, so the simplest way is
to have exclusive locks when you want to register a transaction on a specific stock. Having multiple servers prevents you from having
a simple in process (or OS-wide) lock.

## The Answer
There are a lot of solutions to this of course, you can even implement this without an acctual lock ([i.e. Optimistic locking](https://en.wikipedia.org/wiki/Optimistic_concurrency_control)) but these kinds of operations (e.g. financial transactions) are safer with a lock (i.e. [Pessimistic locking](https://en.wikipedia.org/wiki/Lock_(computer_science)))

So you may want to implement critical code on a single machine and make other servers to forward
their requests to this single server, by doing that you're making a [single point of failure](https://en.wikipedia.org/wiki/Single_point_of_failure),
Thus when this single server goes down, every other dependent server will go down and
they can't serve until this single server is resurrected or is replaced with another server.

Another approach is to have all servers work independently, but when they want to lock something, they ask a remote server
(the coordinator) to allow them to do their job and prevent others to work on the same thing concurrently. This is acctually a
good solution but it has it's drawbacks. For instance this is still a single point of failure, but in most cases it doesn't matter
and it's acceptable for servers to have downtime for a short time.

But if you want to eliminate every chance of failure or at least make it so little you can implement a disctributed lock manager (DLM)
and use it to lock more reliably in multiple cluster servers.


## Exclusive Locks
The minimum thing we require to implement a simple exclusive lock is the atomic operation
[Compare-and-swap](https://en.wikipedia.org/wiki/Compare-and-swap) (aka compare-exchange), so you can implement a lock everywhere
that a compare-and-swap is available.

```c++
//C++

volatile int isLock = 0;

//compare_and_swap compares isLock to 0, if they are equal then it sets the
//isLock to 1 and returns true, and if they are not equal it returns false.
while (!compare_and_swap(&isLock, 0, 1)) {
    //do nothing (busy-burn the CPU), or yield the time-slice (e.g. Thread.Yield()).
}

//Lock is acquired here.

//And for unlocking simply set value of isLock to zero,
//    but it's better to use a write barrier/fence to force
//    the CPU to write data back to RAM asap and in order. [3]
```


## Deadlocks
The most important problem when dealing with pessimistic locks is a [deadlock](https://en.wikipedia.org/wiki/Deadlock), and it's more common
in more complicated scenarios specially in distributed locks where network and other problems could intervene between the lock manager and
the lock user. 

```csharp
//C#

object lock1 = new object();
object lock2 = new object();

var t1 = new Thread(() => {

    Monitor.Enter(lock1);

    Console.WriteLine("Lock 1 acquired by thread 1");

    Thread.Sleep(1000);

    Monitor.Enter(lock2);

    Console.WriteLine("Lock 2 acquired by thread 1");

    Monitor.Exit(lock1);
    Monitor.Exit(lock2);

    Console.WriteLine("thread1 release all locks");

});

var t2 = new Thread(() => {
    
    Monitor.Enter(lock2);

    Console.WriteLine("Lock 2 acquired by thread 2");

    Thread.Sleep(1000);

    Monitor.Enter(lock1);

    Console.WriteLine("Lock 1 acquired by thread 2");

    Monitor.Exit(lock2);
    Monitor.Exit(lock1);

    Console.WriteLine("thread2 release all locks");

});

t1.Start();
t2.Start();

t1.Join();
t2.Join();

//This line will never be reached.

```

## Lock Timeout
One way to prevent deadlocks is to have a timeout of locks, so when a client fails to release the lock, it automatically is being released by the lock manager.
But it can be source of many other problems, like what if a lock times-out without the client finishes it's job and another client acquires the lock
and start working on the same transaction? in this case we could have integrity problems in the data. A fencing token would be an answer to this problem.


## Concurrency Tokens
The opposite to pessimistic locks are optimistic locks. For instance you can have a concurrency field in your table so you could change the entity and
when you want to commit the changes, check whether the entity has the previous concurrency token as you have in memory and if they are equal it's
safe to commit, and if they are not equal you should rollback (and somehow handle the error). The same mechanism can be used in distributed locks.


## Fencing Tokens
Having utilized the lock timeout may cause problems, like what if an older lock times-out and 


## Redis As Lock Server
Redis as an in-memory store supports compare-and-swap operations so you can use redis
as your lock server.


---


### Footnotes
1. [Single point of failure](https://en.wikipedia.org/wiki/Single_point_of_failure)
2. [Compare-and-swap](https://en.wikipedia.org/wiki/Compare-and-swap)
3. [Memory barrier](https://en.wikipedia.org/wiki/Memory_barrier)
