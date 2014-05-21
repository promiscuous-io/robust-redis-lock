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
    @key      = (options[:namespace] || self.class.namespace) + ":" + key

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
      sleep @sleep.to_f
    end

    yield if (block_given? && result == true)

    result
  ensure
    unlock if block_given?
  end

  def try_lock
    now = Time.now.to_i

    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@lock_script ||= Script.new <<-LUA
        local key = KEYS[1]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local token_key = 'redis:lock:token'

        local prev_expires_at = tonumber(redis.call('hget', key, 'expires_at'))
        if prev_expires_at and prev_expires_at > now then
          return {'locked', nil}
        end

        local next_token = redis.call('incr', token_key)

        redis.call('hset', key, 'expires_at', expires_at)
        redis.call('hset', key, 'token', next_token)

        if prev_expires_at then
          return {'recovered', next_token}
        else
          return {'acquired', next_token}
        end
    LUA
    result, token = @@lock_script.eval(@redis, :keys => [@key], :argv => [now, now + @expire])

    @token = token if token

    case result
    when 'locked'    then return false
    when 'recovered' then return :recovered
    when 'acquired'  then return true
    end
  end

  def unlock
    # Since it's possible that the operations in the critical section took a long time,
    # we can't just simply release the lock. The unlock method checks if @expire_at
    # remains the same, and do not release when the lock timestamp was overwritten.
    @@unlock_script ||= Script.new <<-LUA
        local key = KEYS[1]
        local token = ARGV[1]

        if redis.call('hget', key, 'token') == token then
          redis.call('del', key)
          return true
        else
          return false
        end
    LUA
    result = @@unlock_script.eval(@redis, :keys => [@key], :argv => [@token])
    !!result
  end

  def extend
    now  = Time.now.to_i
    @@extend_script ||= Script.new <<-LUA
        local key = KEYS[1]
        local expires_at = tonumber(ARGV[1])
        local token = ARGV[2]

        if redis.call('hget', key, 'token') == token then
          redis.call('hset', key, 'expires_at', expires_at)
          return true
        else
          return false
        end
    LUA
    !!@@extend_script.eval(@redis, :keys => [@key], :argv => [now + @expire, @token])
  end
end
