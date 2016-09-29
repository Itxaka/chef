#
# Author:: Daniel DeLeo (<dan@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require File.expand_path('../../spec_helper', __FILE__)
require 'chef/client'

describe Chef::RunLock do

  # This behavior is believed to work on windows, but the tests use UNIX APIs.
  describe "when locking the chef-client run", :unix_only => true do
    let(:random_temp_root){ "/tmp/#{Random.rand(Time.now.to_i + Process.pid)}" }

    let(:file_cache_path){ "/var/chef/cache" }
    let(:lockfile){ "#{random_temp_root}/this/long/path/does/not/exist/chef-client-running.pid" }

    after(:each){ FileUtils.rm_r(random_temp_root) }

    it "creates the full path to the lockfile" do
      run_lock = Chef::RunLock.new(:file_cache_path => file_cache_path, :lockfile => lockfile)
      lambda { run_lock.acquire }.should_not raise_error(Errno::ENOENT)
      File.should exist(lockfile)
    end

    it "allows only one chef client run per lockfile" do
      read, write = IO.pipe
      run_lock = Chef::RunLock.new(:file_cache_path => file_cache_path, :lockfile => lockfile)
      p1 = fork do
        run_lock.acquire
        write.puts 1
        #puts "[#{Time.new.to_i % 100}] p1 (#{Process.pid}) running with lock"
        sleep 2
        write.puts 2
        #puts "[#{Time.new.to_i % 100}] p1 (#{Process.pid}) releasing lock"
        run_lock.release
      end

      p2 = fork do
        run_lock.acquire
        write.puts 3
        #puts "[#{Time.new.to_i % 100}] p2 (#{Process.pid}) running with lock"
        run_lock.release
      end

      Process.waitpid2(p1)
      Process.waitpid2(p2)

      write.close
      order = read.read
      read.close

      order.should == "1\n2\n3\n"
    end

    it "clears the lock if the process dies unexpectedly" do
      read, write = IO.pipe
      run_lock = Chef::RunLock.new(:file_cache_path => file_cache_path, :lockfile => lockfile)
      p1 = fork do
        run_lock.acquire
        write.puts 1
        #puts "[#{Time.new.to_i % 100}] p1 (#{Process.pid}) running with lock"
        sleep 1
        write.puts 2
        #puts "[#{Time.new.to_i % 100}] p1 (#{Process.pid}) releasing lock"
        run_lock.release
      end

      p2 = fork do
        run_lock.acquire
        write.puts 3
        #puts "[#{Time.new.to_i % 100}] p2 (#{Process.pid}) running with lock"
        run_lock.release
      end
      Process.kill(:KILL, p1)

      Process.waitpid2(p1)
      Process.waitpid2(p2)

      write.close
      order = read.read
      read.close

      order.should =~ /3\Z/
    end
  end

end

