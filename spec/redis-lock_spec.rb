require 'spec_helper'

describe RedisLock do
  subject       { RedisLock.new(key, options) }
  let(:redis)   { Redis.new }
  let(:key)     { 'key' }
  let(:options) { { :timeout => 0.5.second, :expire => 0.5.second } }

  before { RedisLock.redis = redis }

  it "can lock and unlock" do
    subject.lock

    subject.locked?.should == true

    subject.unlock

    subject.locked?.should == false
  end

  it "blocks if a lock is taken for the duration of the timeout" do
    subject.lock
    unlocked = false

    Thread.new { subject.lock; unlocked = true }

    unlocked.should == false

    sleep 1

    unlocked.should == true
  end

  it "expires the lock after the lock timeout" do
    subject.lock
    sleep 1

    subject.lock.should == :recovered
    subject.locked?.should == true
  end
end
