class Redis::Lock::Script
  def initialize(script)
    @script = script
    @sha = Digest::SHA1.hexdigest(@script)
  end

  def eval(redis, options={})
    redis.evalsha(@sha, options)
  rescue ::Redis::CommandError => e
    if e.message =~ /^NOSCRIPT/
      redis.script(:load, @script)
      retry
    end
    if e.message =~ /^ERR unknown command/
      raise "You are using a version of Redis that does not support LUA scripting. Please use Redis 2.6.0 or greater"
    end
    raise e
  end

  def to_s
    @script
  end
end

