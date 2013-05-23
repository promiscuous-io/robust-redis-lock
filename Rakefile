def run(cmd)
  exit(1) unless Kernel.system(cmd)
end

desc 'Run specs for each gemfile'
task :specs do
  run "bundle --quiet"
  run "bundle exec rspec spec"
end

task :default => :specs
