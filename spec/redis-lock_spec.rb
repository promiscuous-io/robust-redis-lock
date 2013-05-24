require 'spec_helper'

describe Redis::Lock do
  subject       { Redis::Lock.new(key, options) }
  let(:redis)   { Redis.new }
  let(:key)     { 'key' }
  let(:options) { { :timeout => 0.5, :expire => 0.5 } }

  before { Redis::Lock.redis = redis }

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
