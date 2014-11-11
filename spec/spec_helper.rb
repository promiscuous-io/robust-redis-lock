require 'rubygems'
require 'bundler'

Bundler.require

Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.color = true

  redis_url = ENV["BOXEN_REDIS_URL"] || "redis://localhost/"
  redis = Redis.new(:url => redis_url)
  Redis::Lock.redis = redis

  config.before(:each) do
    Redis::Lock.redis.flushdb
  end
end
