require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/*_test.rb"]
  task.warning = true
end

# gem build copies file permissions, so a checkout made under a restrictive
# umask (e.g. 077) would ship files other users cannot read.
task :readable_files do
  Gem::Specification.load("tmux.gemspec").files.each do |path|
    File.chmod(File.stat(path).mode | 0o444, path)
  end
end
task build: :readable_files

desc "Render the README screenshots from real tmux sessions (needs tmux, vhs, ttyd, ffmpeg)"
task :screenshots do
  ruby "script/screenshots", *ENV.fetch("SCENES", "").split
end

# The tmux versions CI tests besides the runners' own: the oldest supported
# release, the newest release of each later minor version, and the
# development branch. Keep in sync with .github/workflows/ci.yml.
TMUX_VERSIONS = %w[3.2a 3.3a 3.4 3.5a 3.6b 3.7c 3.8 master].freeze

desc "Run the tests against tmux built from source (VERSIONS=\"3.2a 3.8\" picks some)"
task "test:tmux" do
  versions = ENV.fetch("VERSIONS", TMUX_VERSIONS.join(" ")).split
  failed = versions.reject do |version|
    binary = `script/build-tmux #{version}`.strip
    abort "could not build tmux #{version}" unless $?.success?

    puts "== #{`#{binary} -V`.strip}"
    path = "#{File.dirname(binary)}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
    system({"PATH" => path, "CI" => "1"}, FileUtils::RUBY, "-S", "rake", "test")
  end
  abort "tests failed on tmux #{failed.join(', ')}" unless failed.empty?
end

task default: :test
