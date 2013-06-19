Robust Redis Lock [![Build Status](https://travis-ci.org/crowdtap/robust-redis-lock.png?branch=master)](https://travis-ci.org/crowdtap/robust-redis-lock) [![Gem Version](https://badge.fury.io/rb/robust-redis-lock.png)](http://badge.fury.io/rb/robust-redis-lock)
======

This is a robust redis lock that ensures that only one process can access a
critical section of code.

Unlike the many other implementations available, this implemebtation ensures
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

Usage
-----

```ruby
  Redis::Lock.redis = Redis.new
  lock = Redis::Lock.new('lock_name')
  lock.lock do
    # Critical section
  end
```

Advanced
--------

The following options can be passed into the lock method (default values are
listed):

```ruby
  Redis::lock.new('lock_name', :redis     => Redis::Lock.redis,
                               :timeout   => 60, # seconds
                               :expire    => 60, # seconds
                               :sleep     => 0.1, # seconds
                               :namespace => 'redis:lock')
```

If the lock has expired within the specified `:expire` value then the lock method
will return `:recovered`, otherwise it will return `true` if it has been acquired
or `false` if it could not be acquired within the specified `:timeout` value.

Note that if a lock is recovered there is no guarantee that the other process
has died vs. that it is a slow running process. Therefore be very mindful of what
expiration value you set as a value too low can result in multiple processes
accessing the critical section. If you have recovered a lock you should cleanup
for the dead process if its possible to get into an unstable state.


Requirements
------------
* Redis 2.6+ (clustered redis is **not** supported)


License
-------
Copyright (C) 2013 Crowdtap

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
