require 'resque'
require 'unirest'
require 'hash_at_path'
require 'rack/utils'
require 'json'

class Upgrade

  @queue = ENV['UPGRADE_QUEUE'] || :rancher_upgrade

  def self.before_perform (image_uuid, config, service=nil)
    @config = config
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{severity}] #{msg}\n"
    end
    @logger.level = Logger::DEBUG
  end

  def self.perform (image_uuid, config, service=nil)
    @logger.info ">>> BEGIN #{image_uuid} (#{config['RANCHER_URL']})"
    @config = config

    if service == nil
      @logger.info "Finding services with image #{image_uuid}"
      response = self.rancher_api(:get, '/services')
      services = response.body['data']
    else
      @logger.info "Finding service #{service[:name]} (#{service[:id]})"
      response = self.rancher_api(:get, "/services/#{service[:id]}")
      services = [response.body]
    end

    target_services = services
        .select { |s| s.at_path('launchConfig/imageUuid') == image_uuid }
        .map { |s|
          {
            id: s['id'],
            name: s['name'],
            image_uuid: s['launchConfig']['imageUuid'],
            state: s['state'],
          }
        }
    @logger.info "Found #{target_services.size} service(s) to upgrade"

    for service in target_services
      if service[:state] == 'upgraded'
        @logger.info "Service #{service[:name]} is in upgraded state, confirming..."
        self.service_action(service, 'finishupgrade')
        Resque.enqueue_in(30, self, image_uuid, config, service)
      elsif service[:state] == 'active'
        params = self.create_data service[:image_uuid]
        self.service_action(service, 'upgrade', params=params)
      else
        @logger.info "Service #{service[:name]} is in state #{service[:state]}, retrying in 30s..."
        Resque.enqueue_in(30, self, image_uuid, config, service)
      end
    end

    @logger.info "<<< END"
  end

  # helper
  def self.create_data (image_uuid, start_first=true)
    {
      inServiceStrategy: {
        launchConfig: {
          imageUuid: image_uuid,
          labels: {
            "io.rancher.container.pull_image" => "always"
          }
        },
        startFirst: start_first
      },
      toServiceStrategy: nil
    }
  end

  # helper
  def self.rancher_api (method, path, params = {})
    base_url = @config["RANCHER_URL"]
    url = "#{base_url}#{path}"
    headers = { "Accept": 'application/json', "Content-Type": "application/json" }
    auth = {
      user: @config["RANCHER_ACCESS_KEY"],
      password: @config["RANCHER_SECRET_KEY"]
    }

    @logger.debug "#{method.upcase}: #{url}"
    @logger.debug "params: #{JSON.generate(params)}" if params.size > 0
    if method == :post
      response = Unirest.post(url, auth: auth, headers: headers, parameters: params)
    elsif method == :get
      response = Unirest.get(url, auth: auth, headers: headers, parameters: params)
    end
    @logger.debug "#{response.code} #{Rack::Utils::HTTP_STATUS_CODES[response.code]}"

    if response.code >= 400
      @logger.error response.body
    end

    return response
  end

  # helper
  def self.service_action(service, action, params = {})
    @logger.info "[#{action}] #{service[:name]} (#{service[:id]})"
    self.rancher_api(:post, "/services/#{service[:id]}?action=#{action}", params=params)
  end

end
