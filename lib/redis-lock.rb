require 'redis'
require 'robust-redis-lock/script'

class Redis::Lock
  attr_reader :key

  class << self
    attr_accessor :redis
    attr_accessor :timeout
    attr_accessor :sleep
    attr_accessor :expire
  end

  self.timeout = 60
  self.expire  = 60
  self.sleep   = 0.1

  def initialize(key, options={})
    @key      = key
    @redis    = options[:redis] || self.class.redis
    raise "key cannot be nil" if @key.nil?
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
    now = nil
    @redis.time.tap do |seconds, ms|
      now        = (seconds + (ms/1000))*1000
      @expire_at = (now + @expire).to_i
    end
    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@lock_script ||= Script.new <<-SCRIPT
        local key = KEYS[1]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local lock_value = expires_at
        local current_key_value = redis.call('get', key)

        if current_key_value and tonumber(current_key_value) > now then return false end
        redis.call('set', key, expires_at)

        if current_key_value then return 'recovered' else return true end
    SCRIPT
    result = @@lock_script.eval(@redis, :keys => [@key], :argv => [now, @expire_at])
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
    @@unlock_script.eval(@redis, :keys => [@key], :argv => [@expire_at])
  end

  def locked?
    @redis.get(@key) == @expire_at.to_s
  end
end
