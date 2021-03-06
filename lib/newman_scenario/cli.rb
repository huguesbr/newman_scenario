require 'thor'

module NewmanScenario
  class CLI < Thor
    default_task :run_scenario

    desc "run_scenario environment scenario", "Run scenario using environment"
    long_desc <<~EOF

    `run_scenario environment scenario` will run the custom saved scenario "scenario"
    using postman environment "environment"

    `run_scenario` will prompt for the postman environment to use and create or re-used an existing scenario
    EOF
    method_option :no_prompt, :aliases => "-x", :desc => "No prompt"
    method_option :bail, :aliases => "-b", :desc => "Bailed after first request test failure"
    def run_scenario( environment = nil, scenario = nil )
      Scenario.new.run(scenario_name: scenario, environment_name: environment, bail: options[:bail], no_prompt: options.key?(:no_prompt))
    end

    desc "configure", "configure Postman vs newman_scenario"
    long_desc <<~EOF

    `newman_scenario` needs some information about Postman environments and collections
    Configure will prompt you for each and optionally save them to `.env`
    EOF
    def configure( )
      Scenario.configure
    end
  end
end
