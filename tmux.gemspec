require_relative "lib/tmux/version"

Gem::Specification.new do |spec|
  spec.name = "tmux"
  spec.version = Tmux::VERSION
  spec.summary = "A readable Ruby DSL that compiles to native tmux configuration"
  spec.description = <<~TEXT
    tmux.rb compiles structured Ruby into deterministic tmux configuration and
    format strings. Ruby runs only while building; tmux evaluates the output
    natively, so status rendering never spawns Ruby.
  TEXT
  spec.homepage = "https://github.com/cosmicbuffalo/tmux.rb"
  spec.authors = ["Nick deLannoy"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "prism", ">= 0.19", "< 2"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "bin/*", "README.md", "CHANGELOG.md", "LICENSE"] }
  spec.bindir = "bin"
  spec.executables = ["tmux.rb", "tmux_rb"]
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }
end
