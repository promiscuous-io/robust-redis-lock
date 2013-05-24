require 'spec_helper'

describe Redis::Lock do
  subject       { Redis::Lock.new(key, options) }
  let(:redis)   { Redis.new }
  let(:key)     { 'key' }
  let(:options) { { :timeout => 1, :expire => 1 } }

  before { Redis::Lock.redis = redis }

  it "can lock and unlock" do
    subject.lock

    subject.lockable?.should == false

    subject.unlock

    subject.lockable?.should == true
  end

  it "blocks if a lock is taken for the duration of the timeout" do
    subject.lock
    unlocked = false

    Thread.new { subject.lock; unlocked = true }

    unlocked.should == false

    sleep 1.5

    unlocked.should == true
  end

  it "expires the lock after the lock timeout" do
    subject.lock

    subject.lockable?.should == false
    sleep 1.5

    subject.lockable?.should == :recovered
    subject.lock.should == :recovered
  end
end
