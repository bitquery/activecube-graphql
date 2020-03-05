
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "activecube/graphql/version"

Gem::Specification.new do |spec|
  spec.name          = "activecube-graphql"
  spec.version       = Activecube::Graphql::VERSION
  spec.authors       = ["Aleksey Studnev"]
  spec.email         = ["astudnev@gmail.com"]

  spec.summary       = %q{Multi-Dimensional Queries using GraphQL}
  spec.description   = %q{This GEM adapts the GraphQL interface to Activecube multi-dimensional queries. Now you can use GraphQL
to query cubes}
  spec.homepage      = "https://github.com/bitquery/activecube-graphql"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'activecube', '~> 0.1.6'
  spec.add_runtime_dependency 'graphql', '~> 1.9'

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
