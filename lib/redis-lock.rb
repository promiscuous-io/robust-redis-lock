require 'redis'
require 'active_support/core_ext'
require 'robust-redis-lock/script'

class RedisLock
  attr_reader   :key
  cattr_accessor :redis

  def initialize(key, options={})
    raise "key cannot be nil" if key.nil?

    @key      = key
    @timeout  = options[:timeout] || 10.seconds
    @sleep    = options[:sleep]   || 0.1.seconds
    @expire   = options[:expire]  || 10.seconds
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
    now = Time.now.to_i
    @expires_at = now + @expire + 1
    @token = Random.rand(1000000000)

    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@lock_script ||= Script.new <<-SCRIPT
        local key = KEYS[1]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local token = ARGV[3]
        local lock_value = expires_at .. ':' .. token
        local key_value = redis.call('get', key)

        if key_value and tonumber(key_value:match("([^:]*):"):rep(1)) > now then return false end
        redis.call('set', key, lock_value)

        if key_value then return 'recovered' else return true end
    SCRIPT
    result = @@lock_script.eval(redis, :keys => [@key], :argv => [now, @expires_at, @token])
    return :recovered if result == 'recovered'
    !!result
  end

  def unlock
    # Since it's possible that the operations in the critical section took a long time,
    # we can't just simply release the lock. The unlock method checks if @expires_at
    # remains the same, and do not release when the lock timestamp was overwritten.
    @@unlock_script ||= Script.new <<-SCRIPT
        local key = KEYS[1]
        local expires_at = ARGV[1]
        local token = ARGV[2]
        local lock_value = expires_at .. ':' .. token

        if redis.call('get', key) == lock_value then
          redis.call('del', key)
          return true
        else
          return false
        end
    SCRIPT
    @@unlock_script.eval(redis, :keys => [@key], :argv => [@expires_at, @token])
  end

  def locked?
    redis.get(@key) == "#{@expires_at}:#{@token}"
  end
end
