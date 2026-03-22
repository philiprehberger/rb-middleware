# frozen_string_literal: true

require_relative 'lib/philiprehberger/middleware/version'

Gem::Specification.new do |spec|
  spec.name          = 'philiprehberger-middleware'
  spec.version       = Philiprehberger::Middleware::VERSION
  spec.authors       = ['Philip Rehberger']
  spec.email         = ['me@philiprehberger.com']

  spec.summary       = 'Generic middleware stack for composing processing pipelines'
  spec.description   = 'A composable middleware stack that supports lambda and class-based middleware, ' \
                       'named entries with insert-before/after and removal, and sequential execution ' \
                       'with short-circuit capability.'
  spec.homepage      = 'https://github.com/philiprehberger/rb-middleware'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri']          = spec.homepage
  spec.metadata['source_code_uri']       = spec.homepage
  spec.metadata['changelog_uri']         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri']       = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']
end
