require 'spec_helper'

describe Redis::Lock do
  subject       { Redis::Lock.new(key, options) }
  let(:key)     { 'key' }

  context 'when the timeout is less then the expiration' do
    let(:options) { { :timeout => 1, :expire => 1.5 } }

    it 'prefixes with the namespace' do
      subject.lock

      Redis::Lock.redis.hgetall(Redis::Lock::NAMESPACE + ':' + subject.key).should_not be_empty
    end

    context 'using lock/unlock' do
      it "can lock and unlock" do
        subject.lock

        subject.try_lock.should == false

        subject.try_unlock.should == true

        subject.try_lock.should == true
      end

      it "blocks if a lock is taken for the duration of the timeout" do
        subject.lock
        unlocked = false

        Thread.new { subject.lock rescue nil; unlocked = true }

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

      it "updates the lock in the list of expired locks" do
        subject.lock

        sleep 2
        subject.try_lock.should == :recovered

        Redis::Lock.all.should =~ [subject]
      end

      it "raises if trying to unlock a lock that has been recovered" do
        subject.lock

        sleep 2
        Redis::Lock.new(key, options).try_lock

        expect { subject.unlock }.to raise_error(Redis::Lock::LostLock)
      end

      it "can extend the lock" do
        subject.lock

        subject.try_lock.should == false

        sleep 2
        subject.try_extend.should == true

        subject.try_lock.should == false
      end

      it "will not extend the lock if taken by another instance" do
        subject.lock

        subject.try_lock.should == false

        sleep 2
        Redis::Lock.new(key, options).try_lock.should == :recovered

        subject.try_extend.should == false
      end

      it 'raises if the lock is taken' do
        subject.lock

        expect { subject.lock }.to raise_error(Redis::Lock::Timeout)
      end

      it 'raises if trying to unlock a lock that has not been acquired' do
        expect { subject.try_unlock }.to raise_error(Redis::Lock::NotLocked)
      end

      it 'raises if unlocking a locked lock twice' do
        subject.lock; subject.unlock

        expect { subject.try_unlock }.to raise_error(Redis::Lock::NotLocked)
      end

      it 'raises if trying to extend a lock that has not been acquired' do
        expect { subject.try_extend }.to raise_error(Redis::Lock::NotLocked)
      end
    end

    context 'using synchronize' do
      it "can lock" do
        subject.synchronize do
          subject.try_lock.should == false
        end
        subject.try_lock.should == true
      end

      it "ensures that the lock is unlocked when locking with a block" do
        begin
          subject.synchronize do
            raise "An error"
          end
        rescue
        end

        subject.try_lock.should == true
      end

      it "does not run the critical section if the lock times out" do
        subject.lock

        critical = false

        expect { subject.synchronize { critical = true } }.to raise_error(Redis::Lock::Timeout)

        critical.should == false
      end

      it "returns the value returned by the block" do
        subject.synchronize { 'a' }.should == 'a'
      end

      context 'when the expiration time is less then the timeout' do
        let(:options) { { :timeout => 1.5, :expire => 1 } }

        it "does not raise when the lock is recovered, executes the block with the lock taken and unlocks" do
          called = false
          locked = false
          subject.lock

          expect {
            Redis::Lock.new(subject.key, options).synchronize do
              called = true
              locked = !Redis::Lock.new(subject.key).try_lock
            end
          }.to_not raise_error
          called.should == true
          locked.should == true
          Redis::Lock.new(subject.key).try_lock.should == true
        end
      end
    end
  end

  context 'when passing in recovery data with a lock' do
    subject       { Redis::Lock.new(key, options) }
    let(:options) { { :timeout => 1, :expire => 0 } }

    context "when data is not a string" do
      let(:data) { { :a => 1 } }

      it "raises" do
        expect { subject.lock(:recovery_data => data) }.to raise_error
      end
    end

    context "when the lock has expired" do
      let(:data)    { "some data" }
      let(:options) { { :timeout => 1, :expire => 0.0 } }

      before do
        subject.lock(:recovery_data => data)
        sleep 1
      end

      it "returns the data when a recovered lock is extended" do
        lock = Redis::Lock.expired.first
        lock.extend

        lock.recovery_data.should == data
      end

      it "returns the data when a recovered lock is extended and the data is stored in the old key" do
        lock = Redis::Lock.expired.first

        Redis::Lock.redis.hdel(lock.namespaced_key, 'recovery_data')
        Redis::Lock.redis.hset(lock.namespaced_key, 'data', data)

        lock.extend

        lock.recovery_data.should == data
      end

      it "raises and does not overwrite the data if attempting to lock twice" do
        2.times do
          begin
            lock = Redis::Lock.new(subject.key, options)
            lock.lock(:recovery_data => "other data")
          rescue Redis::Lock::Recovered
            lock.recovery_data.should == data
          end
        end
      end
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
    let(:expired)   { Redis::Lock.new('1', { :expire => 0,    :key_group => key_group }) }
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

    it "removes the key when locking then recovering an expired lock" do
      lock = Redis::Lock.expired(:key_group => key_group).first

      lock.unlock

      Redis::Lock.all(:key_group => key_group).should == [unexpired]
    end

    it "is possible to extend a lock returned and only allow a recovered lock to be extended once" do
      lock1 = Redis::Lock.expired(:key_group => key_group).first
      lock2 = Redis::Lock.expired(:key_group => key_group).first

      lock1.try_extend.should == true
      lock2.try_extend.should == false

      Redis::Lock.all(:key_group => key_group).should =~ [lock1, unexpired]
    end

    it 'extending a lock updates the list of expired locks' do
      Redis::Lock.expired(:key_group => key_group).first.extend

      Redis::Lock.all(:key_group => key_group).should =~ [expired, unexpired]
    end
  end

  context "with keys that contain ':'" do
    let(:expired)   { Redis::Lock.new('1:1:1', { :expire => 0 }) }

    before do
      expired.lock
      sleep 1
    end

    it "returns all locks that are expired" do
      Redis::Lock.expired.should == [expired]
    end
  end
end
