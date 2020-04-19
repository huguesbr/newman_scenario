require 'tty-prompt'
require 'json'
require 'httparty'
require 'dotenv/load'

module NewmanScenario
  class Error < StandardError; end
  class ConfigurationError < StandardError; end

  class Scenario
    DEFAULT_CUSTOM_SCENARIOS_FILE_PATH = 'newman_scenarios.json'.freeze
    DEFAULT_LAST_SCENARIO_FILE_PATH = '/tmp/last_newman_scenario.json'.freeze

    @default_collection_id = ENV['NEWMAN_SCENARIO_COLLECTION_ID']
    @default_environment_ids = nil
    @default_api_key = ENV['POSTMAN_API_KEY']
    @default_custom_scenarios_file_path = ENV['NEWMAN_SCENARIO_CUSTOM_COLLECTION_FILE_PATH'] || DEFAULT_CUSTOM_SCENARIOS_FILE_PATH
    @default_last_scenario_file_path = ENV['NEWMAN_SCENARIO_LAST_SCENARIO_FILE_PATH'] || DEFAULT_LAST_SCENARIO_FILE_PATH

    class << self
      attr_accessor :default_api_key
      attr_accessor :default_collection_id
      attr_accessor :default_environment_ids
      attr_accessor :default_custom_scenarios_file_path
      attr_accessor :default_last_scenario_file_path

      def configure(default_api_key: nil, default_collection_id: nil, default_environment_ids: nil, default_custom_scenarios_file_path: nil, default_last_scenario_file_path: nil)
        self.default_api_key = default_api_key || prompt.ask('Postman API Key:')
        self.default_collection_id = default_collection_id || prompt.ask('Postman Collection Id:')
        self.default_environment_ids = default_environment_ids
        unless self.default_environment_ids
          self.default_environment_ids = {}
          loop do
            break unless prompt.yes?('Add environment?')

            name = prompt.ask('Environment Name:')
            id = prompt.ask('Environment Id:')
            self.default_environment_ids[name] = id
          end
        end
        self.default_custom_scenarios_file_path = default_custom_scenarios_file_path || prompt.ask('Custom scenarios file path:', value: DEFAULT_CUSTOM_SCENARIOS_FILE_PATH)
        self.default_last_scenario_file_path = default_last_scenario_file_path || prompt.ask('Last scenario file path:', value: DEFAULT_LAST_SCENARIO_FILE_PATH)
        if (env_path = prompt.ask('Save to: [enter to not save]', value: '.env'))
          File.open(env_path, 'a') do |file|
            file.puts "POSTMAN_API_KEY: #{self.default_api_key}"
            file.puts "NEWMAN_SCENARIO_COLLECTION_ID: #{self.default_collection_id}"
            file.puts "NEWMAN_SCENARIO_ENVIRONMENTS: #{self.default_environment_ids.to_json}"
            file.puts "NEWMAN_SCENARIO_CUSTOM_COLLECTION_FILE_PATH: #{self.default_custom_scenarios_file_path}"
            file.puts "NEWMAN_SCENARIO_LAST_SCENARIO_FILE_PATH: #{self.default_last_scenario_file_path}"
          end
        end
      end

      private
      
      def prompt
        @prompt ||= TTY::Prompt.new
      end
    end

    attr_accessor :collection_id
    attr_accessor :environment_ids
    attr_accessor :api_key
    attr_accessor :custom_collection_file_path
    attr_accessor :last_scenario_file_path

    def initialize(collection_id: nil, environment_ids: nil, api_key: nil, custom_collection_file_path: nil, last_scenario_file_path: nil)
      self.collection_id ||= self.class.default_collection_id
      raise ConfigurationError, 'Missing Collection Id' unless self.collection_id

      self.environment_ids ||= self.class.default_environment_ids
      self.environment_ids ||= JSON.parse(ENV['NEWMAN_SCENARIO_ENVIRONMENTS'], symbolize_names: true) if ENV['NEWMAN_SCENARIO_ENVIRONMENTS']
      raise ConfigurationError, 'Missing Environment Ids' unless self.environment_ids

      self.api_key ||= self.class.default_api_key
      raise ConfigurationError, 'Missing Postman API Key' unless self.api_key

      self.custom_collection_file_path ||= self.class.default_custom_scenarios_file_path
      raise ConfigurationError, 'Missing Custom collection file path' unless self.custom_collection_file_path

      self.last_scenario_file_path ||= self.class.default_last_scenario_file_path
      raise ConfigurationError, 'Missing Last scenario file path' unless self.last_scenario_file_path
    rescue ConfigurationError => e
      prompt.warn e
      if prompt.yes?('Configure?')
        self.class.configure
        retry
      end
    end

    def run(environment_name: nil, scenario_name: nil, bail: true, no_prompt: false)
      return if `which newman`.empty? && !prompt_to_install_newman

      prompt_to_set_api_key unless api_key
      environment = environment_ids[environment_name.to_sym] if environment_name
      environment ||= prompt.select("Environment", environment_ids, default: 1)
      load_postman_environment(environment, no_prompt: no_prompt)
      collection = JSON.parse(File.read("/tmp/postman-collection-#{collection_id}.json"), symbolize_names: true)[:collection]
      unless File.exist?(last_scenario_file_path) && (!scenario_name && prompt.yes?('Replay last scenario?'))
        scenarii = read_from_json_file(custom_collection_file_path) || {}
        scenario_name ||= prompt.select('Scenario', ['Custom Scenario'] + scenarii.keys.sort)
        scenario_requests = (scenario_name == 'Custom Scenario' && []) || scenarii[scenario_name]
        if scenario_requests.empty?
          scenario_requests = []
          extract_all_requests = lambda do |item, prefix|
            request_name = "#{prefix.empty? ? '' : "#{prefix}/" }#{item[:name]}"
            request_names = [request_name] + (item[:item]&.map { |child_item| extract_all_requests.call(child_item, request_name) } || [])
            request_names
          end
          all_request_names = extract_all_requests.call(collection, '')
          loop do
            scenario_requests.delete('duplicate')
            scenario_requests += prompt.multi_select("Requests (type to filter prefix, choose duplicate to perform action multiple times)", ['duplicate'] + all_request_names, cycle: true, filter: true)
            break unless scenario_requests.include?('duplicate')

          end
          if prompt.yes?('Save this custom scenario?')
            name = prompt.ask('Name?')
            new_or_overwrite = !scenarii.key?(name) || !prompt.no?('This scenario exist, overwrite it?')
            if new_or_overwrite
              prompt.ok "Adding/Updating #{name} to scenarii"
              scenarii[name] = scenario_requests
              write_to_json_file(custom_collection_file_path, scenarii, pretty: true)
            end
          end
        end
        find_request = lambda do |request_path, items|
          item = items.find { |i| i[:name] == request_path.last }
          if item
            item
          else
            child_item = items.find { |i| i[:name] == request_path.first }
            if child_item
              request_path = request_path.drop(1)
              if request_path.empty?
                child_item
              else
                find_request.call(request_path, child_item[:item])
              end
            end
          end
        end
        requests = scenario_requests.map do |scenario_request|
          find_request.call(scenario_request.split('/'), collection[:item])
        end
        new_collection = {
          collection: {
            info: {
              name: scenario_name,
              schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'
            },
            item: requests
          }
        }
        write_to_json_file(last_scenario_file_path, new_collection)
      end
      cmd("newman run #{last_scenario_file_path} -e /tmp/postman-environment-#{environment}.json#{bail ? ' --bail' : ''}")
    end

    private

    def cmd(command)
      prompt.ok "Running: #{command}"
      `#{command}`
    end

    def prompt
      @prompt ||= TTY::Prompt.new
    end

    def prompt_to_install_newman
      prompt.warn 'missing newman command line'
      return false unless prompt.yes?('Install newman?')

      prompt.ok 'installing newman: brew install newman'
      cmd('brew install newman')
    end

    def prompt_to_set_api_key
      prompt.warn 'Missing Postman API Key'
      prompt.warn 'Get one from: https://YOURPOSTMAN.postman.co/settings/me/api-keys'
      self.api_key = prompt.ask('Postman API Key')
      cmd("echo \"POSTMAN_API_KEY: #{self.api_key}\" >> .env")
    end

    def load_postman_environment(environment, no_prompt: false)
      reload =
        if no_prompt
          false
        else
          !prompt.no?("Refetch postman config?")
        end
      if File.file?("/tmp/postman-environment-#{environment}.json") && !reload
        prompt.ok "reusing env /tmp/postman-environment-#{environment}.json"
      else
        prompt.ok "fetching environment #{environment}"
        fetch_postman_to_file("/environments/#{environment}", "/tmp/postman-environment-#{environment}.json")
      end
      if File.file?('/tmp/postman-collection.json') && !reload
        prompt.ok "reusing collection /tmp/postman-collection.json"
      else
        prompt.ok "fetching collection #{collection_id}"
        fetch_postman_to_file("/collections/#{collection_id}", "/tmp/postman-collection-#{collection_id}.json")
      end
    end

    def fetch_postman_to_file(url_path, file_path)
      response = HTTParty.get("https://api.getpostman.com/#{url_path}", headers: { 'X-Api-Key' => api_key})
      raise Error, "Invalid response code: #{response.code}" unless response.code == 200

      File.open(file_path, 'w+') do |file|
        file.puts response.body
      end
    end

    def write_to_json_file(file, hash, pretty: false)
      data =
        if pretty
          JSON.pretty_generate(hash)
        else
          hash.to_json
        end
      open(file, 'w') { |f| f.puts data }
    end

    def read_from_json_file(file, symbolize_names: false)
      return unless File.file?(file)

      JSON.parse(File.read(file), symbolize_names: symbolize_names)
    end
  end
end
