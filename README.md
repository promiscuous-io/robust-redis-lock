Robust Redis Lock [![Build Status](https://travis-ci.org/crowdtap/robust-redis-lock.png?branch=master)](https://travis-ci.org/crowdtap/robust-redis-lock) [![Gem Version](https://badge.fury.io/rb/robust-redis-lock.png)](http://badge.fury.io/rb/robust-redis-lock)
======

This is a robust redis lock that ensures that only one process can access a
critical section of code.

Unlike the many other implementations available, this implementation ensures
that an orphaned lock eventually expires in a safe (non-racy) manner. LUA scripting
made available in Redis 2.6 makes this possible.

Install
-------

```ruby
gem install robust-redis-lock
```
or add the following line to your Gemfile:
```ruby
gem 'robust-redis-lock'
```
and run `bundle install`

Usage (Basic)
-----

Similar to Mutex#synchronize, use synchronize to ensure only one process/thread accesses a critical
section. Note that synchronize ensures that a lock is unlocked if an exception is thrown by the block.

```ruby
  Redis::Lock.redis = Redis.new
  lock = Redis::Lock.new('lock_name')
  lock.synchronize do
    # Critical section

    # Extend the lock by the timeout value. This will raise a
    Redis::Lock::LostLock exception if the lock could not be extended
    lock.extend

    # You can also use the try_ version of the all methods if you don't want to raise.
    # Just make sure to check the return value

    unless lock.try_extend
      # You've lost the lock, make sure to deal with this
    end
  end
```

Usage (Advanced)
-----

Use Redis::Lock#lock when you want finer grained control or you need to handle recovered locks (expired locks that have been taken
by another process).

```ruby
  Redis::Lock.redis = Redis.new
  lock = Redis::Lock.new('lock_name')
  begin
    lock.lock
    # Critical Section
    lock.unlock
  rescue Redis::Lock::Timeout
    # Handle a timed out lock
  rescue Redis::Lock::Recovered
    # Handle a recovered lock (clean up for the other process)
  rescue Redis::Lock::LostLock
    # Handle the lock lost when unlocking
  end
```

You can use the `try_lock` if you want to check and return immediately whether the lock is available and not raise.
`try_unlock` and `try_extend` are similar and don't raise. This means you have to check return values... so be careful.

```ruby
  Redis::Lock.redis = Redis.new
  lock = Redis::Lock.new('lock_name')
  case lock.try_lock
  when true
    # Critical section
    unless lock.unlock
      # Handle a lost lock
    end
  when :recovered
    # Lock recovered. Handle this case and then perform critical section
  when false
    # Failed to get lock
  end
```

Recovery data can be passed included and stored on the lock. This is very useful if you need to clean up a recovered lock.

```ruby
  Redis::Lock.redis = Redis.new
  lock = Redis::Lock.new('lock_name')
  begin
    lock.lock(:recovery_data => YAML.dump(some_data))
    # Critical Section
    lock.unlock
  rescue Redis::Lock::Timeout
    # Handle a timed out lock
  rescue Redis::Lock::Recovered
    # Handle a recovered lock (clean up for the other process)
    recover(YAML.load(lock.recovery_data))
    # Now you need to unlock and lock again to perform the original operation
    lock.unlock
    lock.lock(:recovery_data => YAML.dump(some_data))
  rescue Redis::Lock::LostLock
    # Handle the lock lost when unlocking
  end
```

Note that the data must be a string. Use your favorite serializer to marshal data (YAML is great).

Also note that if you recover a lock the recovery data passed into the lock method WILL NOT BE PERSISTED. This is
so that previous recovery data is never overwritten unless explicitly done so through #unlock.

Expired Locks
-------------

If you need to handle recovered data then you'll likely want to run a recovery process to recover expired locks.

```ruby
  Redis::Lock.expired.each do |lock|
    # Do something to clean up the lock
    recover(YAML.load(lock.recovery_data))
    lock.unlock
  end
```

If you have different groups of locks pass in the `:key_group` param when you
create the lock and when retrieving expired locks:

```ruby
  options = { :key_group  => 'a_key_group' }

  lock = Redis::Lock.new('lock_name', options)
  lock.lock

  Redis::Lock.expired(options).each do |lock|
    # Do something to clean up the lock
  end
```


Options
--------

The following options can be passed into the lock method or as class attributes (default values are
listed):

```ruby
  Redis::Lock.new('lock_name', :redis      => Redis::Lock.redis,
                               :timeout    => 60, # seconds
                               :expire     => 60, # seconds
                               :sleep      => 0.1, # seconds,
                               :key_group  => 'default')

  # Probably use this in an initializer
  Redis::Lock.redis = Redis.new
```

Requirements
------------
* Redis 2.6+ (Redis Cluster is not supported... yet)


License
-------
Copyright (C) 2013 Crowdtap

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
