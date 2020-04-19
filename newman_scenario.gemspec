lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "newman_scenario/version"

Gem::Specification.new do |spec|
  spec.name          = "newman_scenario"
  spec.version       = NewmanScenario::VERSION
  spec.authors       = ["Hugues Bernet-Rollande"]
  spec.email         = ["hugues@xdev.fr"]

  spec.summary       = "Allow to run re-usable collection of requests using newman"
  spec.description   = <<~EOF
    Postman doesn't support re-using the same requests in multiple scenario.
    Duplicating request will make it hard to maintain them.

    Newman allow to run a request or requests within a folder, but due to dup
    requests, maintenance, makes it hard to build re-usable "scenario"

    NewmanScenario try to fill this gap.
  EOF
  spec.homepage      = "https://github.com/huguesbr/newman_scenario"
  spec.license       = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/huguesbr/newman_scenario"
  spec.metadata["changelog_uri"] = "https://github.com/huguesbr/newman_scenario/README.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.executables = ["newman_scenario"]

  spec.add_dependency 'tty-prompt', '0.19.0'
  spec.add_dependency 'httparty', '0.16.2'
  spec.add_dependency 'thor', '1.0.1'
  spec.add_dependency 'dotenv', '2.7.5'

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
