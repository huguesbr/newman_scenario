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
    DEBUG = true

    @default_collection_id = ENV['NEWMAN_SCENARIO_COLLECTION_ID']
    @default_environments = nil
    @default_api_key = ENV['POSTMAN_API_KEY']
    @default_custom_scenarios_file_path = ENV['NEWMAN_SCENARIO_CUSTOM_COLLECTION_FILE_PATH'] || DEFAULT_CUSTOM_SCENARIOS_FILE_PATH
    @default_last_scenario_file_path = ENV['NEWMAN_SCENARIO_LAST_SCENARIO_FILE_PATH'] || DEFAULT_LAST_SCENARIO_FILE_PATH

    class << self
      attr_accessor :default_api_key
      attr_accessor :default_collection_id
      attr_accessor :default_environments
      attr_accessor :default_custom_scenarios_file_path
      attr_accessor :default_last_scenario_file_path

      def configure(default_api_key: nil, default_collection_id: nil, default_environments: nil, default_custom_scenarios_file_path: nil, default_last_scenario_file_path: nil)
        self.default_api_key = default_api_key || prompt.ask('Postman API Key (https://YOURPOSTMAN.postman.co/settings/me/api-keys):', value: ENV['POSTMAN_API_KEY'].to_s)
        collections = nil
        environments = nil
        if prompt.yes?('Using workspace?')
          workspaces = fetch_postman('/workspaces', api_key: self.default_api_key).parsed_response&.fetch('workspaces', nil) || []
          workspaces = workspaces.map { |workspace| workspace.slice('name', 'id').values }.to_h
          workspace = prompt.select('Workspace', workspaces)
          workspace = fetch_postman("/workspaces/#{workspace}", api_key: self.default_api_key).parsed_response&.fetch('workspace', nil) || {}
          collections = workspace['collections']
          environments = workspace['environments']
        end
        collections ||= fetch_postman('/collections', api_key: self.default_api_key).parsed_response&.fetch('collections', nil) || []
        collections = collections.map { |collection| collection.slice('name', 'id').values }.to_h
        self.default_collection_id = default_collection_id || prompt.select('Postman Collection', collections, default: 1)
        self.default_environments = default_environments
        unless self.default_environments
          environments ||= fetch_postman('/environments', api_key: self.default_api_key).parsed_response&.fetch('environments', nil) || []
          environments = environments.map { |environment| environment.slice('name', 'id').values }.to_h
          environment_ids = prompt.multi_select('Postman Collection', environments)
          self.default_environments = environments.select { |_, id| environment_ids.include?(id) }
        end
        self.default_custom_scenarios_file_path = default_custom_scenarios_file_path || prompt.ask('Custom scenarios file path:', value: DEFAULT_CUSTOM_SCENARIOS_FILE_PATH)
        self.default_last_scenario_file_path = default_last_scenario_file_path || prompt.ask('Last scenario file path:', value: DEFAULT_LAST_SCENARIO_FILE_PATH)
        if (env_path = prompt.ask('Save to: [enter to not save]', value: '.env'))
          envs = {
            POSTMAN_API_KEY: self.default_api_key,
            NEWMAN_SCENARIO_COLLECTION_ID: self.default_collection_id,
            NEWMAN_SCENARIO_ENVIRONMENTS: self.default_environments.to_json,
            NEWMAN_SCENARIO_CUSTOM_COLLECTION_FILE_PATH: self.default_custom_scenarios_file_path,
            NEWMAN_SCENARIO_LAST_SCENARIO_FILE_PATH: self.default_last_scenario_file_path,
          }
          existing_lines = File.readlines(env_path).reject { |line| envs.keys.include?(line.split(':').first.to_sym) }
          File.open(env_path, 'w+') do |file|
            existing_lines.each { |line| file.puts line }
            file.puts "POSTMAN_API_KEY: #{self.default_api_key}"
            file.puts "NEWMAN_SCENARIO_COLLECTION_ID: #{self.default_collection_id}"
            file.puts "NEWMAN_SCENARIO_ENVIRONMENTS: #{self.default_environments.to_json}"
            file.puts "NEWMAN_SCENARIO_CUSTOM_COLLECTION_FILE_PATH: #{self.default_custom_scenarios_file_path}"
            file.puts "NEWMAN_SCENARIO_LAST_SCENARIO_FILE_PATH: #{self.default_last_scenario_file_path}"
          end
        end
      end

      def fetch_postman(url_path, expected_response_codes: [200], api_key: nil)
        puts "fetching #{url_path}" if DEBUG
        response = HTTParty.get("https://api.getpostman.com#{url_path}", headers: { 'X-Api-Key' => api_key})
        raise Error, "Invalid response code: #{response.code}" unless expected_response_codes.include?(response.code)

        response
      end

      private

      def prompt
        @prompt ||= TTY::Prompt.new
      end
    end

    attr_accessor :collection_id
    attr_accessor :environments
    attr_accessor :api_key
    attr_accessor :custom_collection_file_path
    attr_accessor :last_scenario_file_path

    def initialize(collection_id: nil, environments: nil, api_key: nil, custom_collection_file_path: nil, last_scenario_file_path: nil)
      self.collection_id ||= self.class.default_collection_id
      raise ConfigurationError, 'Missing Collection Id' unless self.collection_id

      self.environments ||= self.class.default_environments
      self.environments ||= JSON.parse(ENV['NEWMAN_SCENARIO_ENVIRONMENTS'], symbolize_names: true) if ENV['NEWMAN_SCENARIO_ENVIRONMENTS']
      raise ConfigurationError, 'Missing Environment Ids' unless self.environments

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

      environment = environments[environment_name.to_sym] if environment_name
      environment ||= prompt.select('Environment', environments, default: 1)
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
            scenario_requests += prompt.multi_select('Requests (type to filter prefix, choose duplicate to perform action multiple times)', ['duplicate'] + all_request_names, cycle: true, filter: true)
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

    def load_postman_environment(environment, no_prompt: false)
      reload =
        if no_prompt
          false
        else
          !prompt.no?('Refetch postman config?')
        end
      if File.file?("/tmp/postman-environment-#{environment}.json") && !reload
        prompt.ok "reusing env /tmp/postman-environment-#{environment}.json"
      else
        prompt.ok "fetching environment #{environment}"
        fetch_postman_to_file("/environments/#{environment}", "/tmp/postman-environment-#{environment}.json")
      end
      if File.file?('/tmp/postman-collection.json') && !reload
        prompt.ok 'reusing collection /tmp/postman-collection.json'
      else
        prompt.ok "fetching collection #{collection_id}"
        fetch_postman_to_file("/collections/#{collection_id}", "/tmp/postman-collection-#{collection_id}.json")
      end
    end

    def fetch_postman_to_file(url_path, file_path, expected_response_codes: [200])
      response = self.class.fetch_postman(url_path, expected_response_codes: expected_response_codes, api_key: api_key)
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
