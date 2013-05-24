require 'redis'

class Redis::Lock
  require 'robust-redis-lock/script'

  attr_reader :key

  class << self
    attr_accessor :redis
    attr_accessor :timeout
    attr_accessor :sleep
    attr_accessor :expire
    attr_accessor :namespace
  end

  self.timeout   = 60
  self.expire    = 60
  self.sleep     = 0.1
  self.namespace = 'redis:lock'

  def initialize(key, options={})
    raise "key cannot be nil" if key.nil?
    @key      = (options[:namespace] || self.class.namespace) + key

    @redis    = options[:redis] || self.class.redis
    raise "redis cannot be nil" if @redis.nil?

    @timeout  = options[:timeout] || self.class.timeout
    @expire   = options[:expire]  || self.class.expire
    @sleep    = options[:sleep]   || self.class.sleep
  end

  def lock
    result = false
    start_at = Time.now
    while Time.now - start_at < @timeout
      break if result = try_lock
      sleep @sleep
    end
    result
  end

  def try_lock
    now = nil; expire_at = nil
    @redis.time.tap do |seconds, us|
      now       = seconds*1000 + (us/1000)
      expire_at = now + @expire*1000
    end
    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@lock_script ||= Script.new @redis, <<-LUA
        local key = KEYS[1]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local lock_value = expires_at
        local current_key_value = tonumber(redis.call('get', key))

        if current_key_value and tonumber(current_key_value) > now then
          return false
        end

        redis.call('set', key, expires_at)

        if current_key_value then
          return 'recovered'
        else
          return true
        end
    LUA
    result = @@lock_script.eval(:keys => [@key], :argv => [now, expire_at])
    if result
      @expire_at = expire_at
    end

    return :recovered if result == 'recovered'
    !!result
  end

  def unlock
    # Since it's possible that the operations in the critical section took a long time,
    # we can't just simply release the lock. The unlock method checks if @expire_at
    # remains the same, and do not release when the lock timestamp was overwritten.
    @@unlock_script ||= Script.new @redis, <<-LUA
        local key = KEYS[1]
        local expire_at = ARGV[1]

        if redis.call('get', key) == expire_at then
          redis.call('del', key)
          return true
        else
          return false
        end
    LUA
    result = @@unlock_script.eval(:keys => [@key], :argv => [@expire_at])
    !!result
  end
end
