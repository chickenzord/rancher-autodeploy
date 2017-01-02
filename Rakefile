require 'dotenv/tasks'
require 'resque/tasks'
require 'resque/scheduler/tasks'

task :config => :dotenv do
  require 'resque'
  redis_host = ENV['REDIS_HOST'] || 'localhost'
  redis_port = ENV['REDIS_PORT'] || '6379'
  Resque.redis = "#{redis_host}:#{redis_port}"
end

namespace :resque do
  task :setup => :dotenv do
    root_path = "#{File.dirname(__FILE__)}"
    require "#{root_path}/src/upgrade.rb"
  end

  task :scheduler => :setup
end

namespace :app do
  task :api => [:config] do
    ruby 'src/app.rb'
  end

  task :scheduler => [:config, "resque:scheduler"]

  task :worker => [:config, "resque:work"]
end
