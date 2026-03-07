# frozen_string_literal: true

require_relative "lib/dex/version"

Gem::Specification.new do |spec|
  spec.name = "dexkit"
  spec.version = Dex::VERSION
  spec.authors = ["Jacek Galanciak"]
  spec.email = ["jacek.galanciak@gmail.com"]

  spec.summary = "dexkit: Rails Patterns Toolbelt. Equip to gain +4 DEX"
  spec.description = "A toolbelt of patterns for your Rails applications: Operation, Event, Form"
  spec.homepage = "https://dex.razorjack.net/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/razorjack/dexkit"
  spec.metadata["changelog_uri"] = "https://github.com/razorjack/dexkit/blob/master/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://dex.razorjack.net/"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ docs/ .git .github appveyor Gemfile]) ||
        f.match?(/\A(AGENTS|CLAUDE)\.md\z|\.rubocop.*\.yml\z|\ARakefile\z/)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activemodel", ">= 6.1"
  spec.add_dependency "literal", "~> 1.9"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies for testing async operations
  spec.add_development_dependency "activejob", ">= 6.1"
  spec.add_development_dependency "activesupport", ">= 6.1"
  spec.add_development_dependency "ostruct"

  # Development dependencies for testing Rails integration
  spec.add_development_dependency "actionpack", ">= 6.1"
  spec.add_development_dependency "activerecord", ">= 6.1"
  spec.add_development_dependency "mongoid", ">= 8.0"
  spec.add_development_dependency "sqlite3", ">= 2.1"
end
