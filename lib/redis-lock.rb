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
    now = nil
    redis.time.tap do |seconds, ms|
      now = (seconds + @expire.seconds)*1000
      @expire_at = (now + (ms/1000)).to_i
    end
    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@lock_script ||= Script.new <<-SCRIPT
        local key = KEYS[1]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local lock_value = expires_at
        local key_expiriation = redis.call('get', key)

        if key_expiriation and tonumber(key_expiriation) > now then return false end
        redis.call('set', key, expires_at)

        if key_expiriation then return 'recovered' else return true end
    SCRIPT
    result = @@lock_script.eval(redis, :keys => [@key], :argv => [now, @expire_at])
    return :recovered if result == 'recovered'
    !!result
  end

  def unlock
    # Since it's possible that the operations in the critical section took a long time,
    # we can't just simply release the lock. The unlock method checks if @expire_at
    # remains the same, and do not release when the lock timestamp was overwritten.
    @@unlock_script ||= Script.new <<-SCRIPT
        local key = KEYS[1]
        local expire_at = ARGV[1]

        if redis.call('get', key) == expire_at then
          redis.call('del', key)
          return true
        else
          return false
        end
    SCRIPT
    @@unlock_script.eval(redis, :keys => [@key], :argv => [@expire_at])
  end

  def locked?
    redis.get(@key) == @expire_at.to_s
  end
end
