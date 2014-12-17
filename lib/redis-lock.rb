require 'redis'
require 'yaml'

class Redis::Lock
  require 'robust-redis-lock/script'

  attr_reader :key

  class << self
    attr_accessor :redis
    attr_accessor :timeout
    attr_accessor :sleep
    attr_accessor :expire
    attr_accessor :namespace
    attr_accessor :key_group
    attr_accessor :serializer
    attr_accessor :data

    def expired(options={})
      self.redis.zrangebyscore(key_group_key(options), 0, Time.now.to_i).map { |key| self.new(key, options) }
    end

    def key_group_key(options)
      [namespace_prefix(options), (options[:key_group] || self.key_group), 'group'].join(':')
    end

    def namespace_prefix(options)
      (options[:namespace] || self.namespace)
    end
  end

  self.timeout    = 60
  self.expire     = 60
  self.sleep      = 0.1
  self.namespace  = 'redis:lock'
  self.key_group  = 'default'
  self.serializer = YAML
  self.data       = nil

  def initialize(key, options={})
    raise "key cannot be nil" if key.nil?
    @options   = options

    namespace_prefix = self.class.namespace_prefix(options) unless key.start_with?(self.class.namespace_prefix(options))
    @key = [namespace_prefix, key].compact.join(':')
    @key_group_key = self.class.key_group_key(@options)

    @redis    = options[:redis] || self.class.redis
    raise "redis cannot be nil" if @redis.nil?

    @timeout    = options[:timeout]    || self.class.timeout
    @expire     = options[:expire]     || self.class.expire
    @sleep      = options[:sleep]      || self.class.sleep
    @serializer = options[:serializer] || self.class.serializer
    @data       = options[:data]       || self.class.data
  end

  def lock
    result = false
    start_at = now
    while now - start_at < @timeout
      break if result = try_lock
      sleep @sleep.to_f
    end

    yield if block_given? && result

    result
  ensure
    unlock if block_given?
  end

  def fetch_data
    unserialize(@redis.hget(key, 'data'))
  end

  def try_lock
    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@lock_script ||= Script.new <<-LUA
        local key = KEYS[1]
        local key_group = KEYS[2]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local data = ARGV[3]
        local token_key = 'redis:lock:token'

        local prev_expires_at = tonumber(redis.call('hget', key, 'expires_at'))
        if prev_expires_at and prev_expires_at > now then
          return {'locked', nil}
        end

        local next_token = redis.call('incr', token_key)

        redis.call('hset', key, 'expires_at', expires_at)
        redis.call('hset', key, 'token', next_token)
        redis.call('hset', key, 'data', data)
        redis.call('zadd', key_group, expires_at, key)

        if prev_expires_at then
          return {'recovered', next_token}
        else
          return {'acquired', next_token}
        end
    LUA
    result, token = @@lock_script.eval(@redis, :keys => [@key, @key_group_key], :argv => [now.to_i, now.to_i + @expire, serialize(@data)])

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
        local key_group = KEYS[2]
        local token = ARGV[1]

        if redis.call('hget', key, 'token') == token then
          redis.call('del', key)
          redis.call('zrem', key_group, key)
          return true
        else
          return false
        end
    LUA
    result = @@unlock_script.eval(@redis, :keys => [@key, @key_group_key], :argv => [@token])
    !!result
  end

  def extend
    @@extend_script ||= Script.new <<-LUA
        local key = KEYS[1]
        local key_group = KEYS[2]
        local expires_at = tonumber(ARGV[1])
        local token = ARGV[2]

        if redis.call('hget', key, 'token') == token then
          redis.call('hset', key, 'expires_at', expires_at)
          redis.call('zadd', key_group, expires_at, key)
          return true
        else
          return false
        end
    LUA
    !!@@extend_script.eval(@redis, :keys => [@key, @key_group_key], :argv => [now.to_i + @expire, @token])
  end

  def now
    Time.now
  end

  def serialize(data)
    @serializer.dump(data)
  end

  def unserialize(data)
    @serializer.load(data)
  end

  def ==(other)
    self.key == other.key
  end
end
