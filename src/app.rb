require 'sinatra'
require 'resque'
require 'dotenv'
require_relative 'upgrade'

Dotenv.load

enable :logging
set :bind, '0.0.0.0'
set :port, '8080'

config = ENV.select { |k,v|
  k.start_with?("RANCHER_") or k.start_with?("AUTODEPLOY_")
}

redis_host = ENV['REDIS_HOST'] || 'localhost'
redis_port = ENV['REDIS_PORT'] || '6379'
Resque.redis = "#{redis_host}:#{redis_port}"

puts '---'
for key,val in config
  puts "#{key}: #{val}"
end
puts '---'

post '/hook' do
  content_type :json

  request.body.rewind
  data = JSON.parse request.body.read

  repo_name = data['repository']['repo_name']
  tag = data['push_data']['tag']
  image_uuid = "docker:#{repo_name}:#{tag}"
  Resque.enqueue(Upgrade, image_uuid, config)

  return {
    status: "accepted",
    data: {
      rancher_url: config["RANCHER_URL"],
      image_uuid: image_uuid
    }
  }.to_json
end
