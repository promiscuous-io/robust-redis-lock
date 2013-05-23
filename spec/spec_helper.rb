require 'rubygems'
require 'bundler'

Bundler.require

Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.color_enabled = true

  config.before do
    redis = Redis.new
    redis.flushdb
    RedisLock.redis = redis
  end
end
