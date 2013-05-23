# encoding: utf-8
$:.unshift File.expand_path("../lib", __FILE__)
$:.unshift File.expand_path("../../lib", __FILE__)

require 'robust-redis-lock/version'

Gem::Specification.new do |s|
  s.name        = "robust-redis-lock"
  s.version     = RedisLock::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Kareem Kouddous"]
  s.email       = ["kareeknyc@gmail.com"]
  s.homepage    = "http://github.com/crowdtap/robust-redis-lock"
  s.summary     = "Robust redis lock"
  s.description = "Robust redis lock"

  s.add_dependency "redis",         ">= 3.0.0"
  s.add_dependency "activesupport", ">= 3.0.0"

  s.files        = Dir["lib/**/*"]
  s.require_path = 'lib'
  s.has_rdoc     = false
end
