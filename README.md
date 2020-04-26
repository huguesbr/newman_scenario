# NewmanScenario

[Newman](https://github.com/postmanlabs/newman) is a command line utility to run [Postman](https://www.postman.com) request(s).
It supports:
- loading a Postman environment file against the requests.
- running a "folder" of requests

It's awesome, but if you want to perform the same request in multiple "folder", you
will end up duplicating this requests, which make it hard to maintain.

Also, it can be clumbersome to add new "scenario" ("folder") from [Postman](https://www.postman.com).

At @babylist, we (I?) use it to feed some pre-built scenario ("create a user", "sign-in", "add a product to the cart", "checkout").
Even if using [Postman](https://www.postman.com) , you can group your requests in a folder ("checkout flow") and run `newman --folder "checkout flow"`, it can be tricky to maintain, if you're re-using "create a user" in different scenarios.

Here comes `NewmanScenario`.

It basically allow you to cherry pick some requests to be chained, saved them (locally), and run
the newly created (locally) "scenario".

The newly builded scenarios are just a list of requests, store in a json format file.
The file is store in the current working directory under `newman_scenarios.json`


## Installation

Add this line to your application's Gemfile:

```ruby
  gem 'newman_scenario'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install newman_scenario

## Demo

    $ rake demo

## Configuration

### Using configure`

configure will guide you to set Postman related collection and environments (fetch from [Postman](https://www.postman.com) and supporting Workspaces), and stores them in `.env`

    $ newman_scenario configure

### Setting `.env` manually

Add this to your `ENV` or `.env`

```
# from https://YOURPOSTMAN.postman.co/settings/me/api-keys
POSTMAN_API_KEY: POSTMAN_API_KEY ()
# postman environments id/name in json format
NEWMAN_SCENARIO_ENVIRONMENTS: {"staging1": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","staging3": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","staging5": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","local": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}
# postman collection id
NEWMAN_SCENARIO_COLLECTION_ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### Rails App

```ruby
# config/initializers/newman_scenario.rb
require 'newman_scenario'

NewmanScenario::Scenario.configure(
  default_api_key: 'PMAK-xxxxxxxxxxxxxxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', # ENV['POSTMAN_API_KEY'], no default value
  default_collection_id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', # ENV['NEWMAN_SCENARIO_COLLECTION_ID'], no default value
  default_environment_ids: { staging: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', production: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'},  # ENV['NEWMAN_SCENARIO_ENVIRONMENTS'] (json format), no default value
  default_custom_scenarios_file_path: 'newman-scenarios.json', # ENV['NEWMAN_SCENARIO_CUSTOM_COLLECTION_FILE_PATH'], default: `newman_scenarios.json`
  default_last_scenario_file_path: '/tmp/last_newman_scenario.json' # ENV['NEWMAN_SCENARIO_LAST_SCENARIO_FILE_PATH'], default: `last_newman_scenario.json`
)
```

## Usage

`NewmanScenario` can be use a stand-alone or within a (Rails) App.

### Stand alone

> running the gem itself will prompt you to select a environment (by it's name, see configuration)
and create or re-use a `NewmanScenario` newly created scenario which can be saved.

    $ newman_scenario

> run with a environment name and/or a scenario name will run the previous created scenario 'Signup' against staging3 environment (with no extra prompt)

    $ newman_scenario staging3 Signup

### Within App

```ruby
require 'newman_scenario'

# will prompt you to select a environment (by it's name, see configuration)
# and create or re-use a `NewmanScenario`
# newly created scenario can be saved
NewmanScenario::Scenario.new.run

# will run the previous created scenario 'Signup' against staging3 environment (with no extra prompt)
NewmanScenario::Scenario.new.run(scenario_name: 'Signup', environment_name: 'staging3', no_prompt: true)
```

## How it works

Beside all the "trivial" Postman collection and environments fetching, it basically scan your collection, cherry pick the requests which match request names stored for a "custom" scenario, create a brand new (local) collection which requests and run this new scenario (collection) using `newman`

## Roadmap

- [x] `NewmanScenario::Scenario.run`
- [ ] Specs :(
- [x] `newman_scenario` cli
- [x] Configure using `NewmanScenario::Scenario.configure` or `newman_scenario configure`
- [x] Fetch available collections and environments from Postman
- [ ] Support for custom scenario variable
- [ ] Support for local environment (no synchronised with Postman)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/huguesbr/newman_scenario. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the `NewmanScenario` project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/huguesbr/newman_scenario/blob/master/CODE_OF_CONDUCT.md).
