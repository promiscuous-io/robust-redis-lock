require 'spec_helper'

describe Redis::Lock do
  subject       { Redis::Lock.new(key, options) }
  let(:key)     { 'key' }

  context 'when the timeout is less then the expiration' do
    let(:options) { { :timeout => 1, :expire => 1.5 } }

    it "can lock and unlock" do
      subject.lock

      subject.try_lock.should == false

      subject.unlock.should == true

      subject.try_lock.should == true
    end

    it "can lock with a block" do
      subject.lock do
        subject.try_lock.should == false
      end
      subject.try_lock.should == true
    end

    it "does not run the critical section if the lock times out" do
      subject.lock

      critical = false

      subject.lock { critical = true }.should == false

      critical.should == false
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

      sleep 2

      unlocked.should == true
    end

    it "expires the lock after the lock timeout" do
      subject.lock

      subject.try_lock.should == false
      sleep 2

      subject.try_lock.should == :recovered
    end

    it "can extend the lock" do
      subject.lock

      subject.try_lock.should == false

      sleep 2
      subject.extend.should == true

      subject.try_lock.should == false
    end

    it "will not extend the lock if taken by another instance" do
      subject.lock

      subject.try_lock.should == false

      sleep 2
      Redis::Lock.new(key, options).extend.should == false

      subject.try_lock.should == :recovered
    end
  end

  context 'when passing in data with a lock' do
    subject       { Redis::Lock.new(key, data, options) }
    let(:options) { { :timeout => 1, :expire => 1.5 } }

    context "when data is a string" do
      let(:data) { "some data" }

      it "serializes" do
        subject.lock

        subject.data.should == data
      end
    end

    context "when data is a hash" do
      let(:data) { { :a => 1, :b => "blah", :c => { :d => true, :e => [1,2,3] }} }

      it "serializes" do
        subject.lock

        subject.data.should == data
      end
    end

    context "when data is fetched from an existing lock" do
      let(:data) { "data from a previous lock" }

      it "fetches" do
        subject.lock
        subject.data.should == data

        second_lock = Redis::Lock.new(subject.key, options)
        second_lock.data.should == data
      end
    end
  end

  context 'when the expiration time is less then the timeout' do
    let(:options) { { :timeout => 1.5, :expire => 1 } }

    it "recovers the lock" do
      subject.lock

      critical = false

      subject.lock { critical = true }.should == :recovered

      critical.should == true
    end
  end
end

describe Redis::Lock, '#expired' do
  context "when there are no expired locks" do
    it "returns an empty array" do
      Redis::Lock.expired.should be_empty
    end
  end

  context "when there are expired locks and unexpired locks" do
    let(:expired)   { Redis::Lock.new('1', { :expire => 0.01, :key_group => key_group }) }
    let(:unexpired) { Redis::Lock.new('2', { :expire => 100,  :key_group => key_group }) }
    let(:key_group) { 'test' }

    before do
      expired.lock
      unexpired.lock
      sleep 1
    end

    it "returns all locks that are expired" do
      Redis::Lock.expired(:key_group => key_group).should == [expired]
    end

    it "only returns locks for the current key_group" do
      Redis::Lock.expired(:key_group => 'xxx').should be_empty
    end

    it "removes the key when locking then unlocking an expired lock" do
      lock = Redis::Lock.expired(:key_group => key_group).first
      lock.lock; lock.unlock

      Redis::Lock.expired(:key_group => key_group).should be_empty
    end
  end
end
