require 'spec_helper'

describe RedisLock do
  subject     { RedisLock.new(key) }
  let(:redis) { Redis.new }
  let(:key)   { 'key' }

  before { RedisLock.redis = redis }

  it "can lock" do
    subject.lock

    subject.locked?.should == true
  end
end
