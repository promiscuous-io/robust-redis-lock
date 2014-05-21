require 'spec_helper'

describe Redis::Lock do
  subject       { Redis::Lock.new(key, options) }
  let(:key)     { 'key' }
  let(:options) { { :timeout => 1, :expire => 1 } }

  it "can lock and unlock" do
    subject.lock

    subject.try_lock.should == false

    subject.unlock.should == true

    subject.try_lock.should == true
  end

  it "does not yield the block if couldn't obtain the lock" do
    flag = false

    subject.lock

    sleep 1.5

    subject.lock do
      flag = true
    end

    flag.should be_false
  end

  it "can lock with a block" do
    subject.lock do
      subject.try_lock.should == false
    end
    subject.try_lock.should == true
  end

  it "ensures that the lock is unlocked when locking with a block" do
    begin
      subject.lock do
        raise "An error"
      end
    rescue
    end

    subject.try_lock.should == true
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

    subject.try_lock.should == false
    sleep 1.5

    subject.try_lock.should == :recovered
  end

  it "can extend the lock" do
    subject.lock

    subject.try_lock.should == false

    sleep 1.5
    subject.extend.should == true

    subject.try_lock.should == false
  end

  it "will not extend the lock if taken by another instance" do
    subject.lock

    subject.try_lock.should == false

    sleep 1.5
    Redis::Lock.new(key, options).extend.should == false

    subject.try_lock.should == :recovered
  end
end
