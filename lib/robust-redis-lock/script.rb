class Redis::Lock::Script
  def initialize(redis, script)
    ensure_redis_version(redis)

    @redis  = redis
    @script = script
    @sha = Digest::SHA1.hexdigest(@script)
  end

  def eval(options={})
    @redis.evalsha(@sha, options)
  rescue ::Redis::CommandError => e
    if e.message =~ /^NOSCRIPT/
      @redis.script(:load, @script)
      retry
    end
    raise e
  end

  def to_s
    @script
  end

  private

  def ensure_redis_version(redis)
    info = redis.info
    version = info['redis_version']
    unless Gem::Version.new(version) >= Gem::Version.new('2.6.0')
      raise "You are using Redis #{version}. Please use Redis 2.6.0 or greater"
    end
  end
end

