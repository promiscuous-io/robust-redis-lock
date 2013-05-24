require 'rubygems'
require 'bundler'

Bundler.require

Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.color_enabled = true

  config.before(:each) do
    redis = Redis.new
    redis.flushdb
    Redis::Lock.redis = redis
  end
end
