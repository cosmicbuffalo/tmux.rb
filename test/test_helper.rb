require "minitest/autorun"
require "minitest/mock"
require "open3"
require "tmpdir"
require_relative "../lib/tmux"

module TmuxTestHelper
  # The oldest tmux the generated configurations support.
  MINIMUM_TMUX = [3, 2].freeze

  # "tmux 3.5a" => [3, 5]; a development build ("tmux next-3.9") by its
  # numbers, and one without numbers ("tmux master") as newest.
  def self.tmux_version
    return @tmux_version if defined?(@tmux_version)

    output = `tmux -V 2>/dev/null`
    @tmux_version = if !$?.success? then nil
    elsif (match = output.match(/(\d+)\.(\d+)/)) then [match[1].to_i, match[2].to_i]
    else [Float::INFINITY, 0]
    end
  end

  # Skips locally without a supported tmux, but fails on CI, where a silently
  # skipped suite would look green.
  def require_tmux!
    version = TmuxTestHelper.tmux_version
    problem = if version.nil? then "tmux is unavailable"
    elsif (version <=> MINIMUM_TMUX).negative?
      "tmux #{version.join('.')} is older than #{MINIMUM_TMUX.join('.')}, the oldest supported"
    end
    return unless problem

    flunk "#{problem} (CI requires it)" if ENV["CI"]
    skip problem
  end

  # Yields a runner for a throwaway tmux server, optionally sourcing `config`
  # first. The socket lives in a temporary directory because tmux leaves
  # socket files behind, and the session runs `sleep` so the user's shell and
  # its rc files never start.
  def with_tmux_server(config = nil)
    require_tmux!
    Dir.mktmpdir("tmux-rb-test") do |directory|
      socket = File.join(directory, "tmux.sock")
      tmux = lambda do |*arguments|
        stdout, stderr, status = Open3.capture3("tmux", "-S", socket, *arguments)
        raise "tmux #{arguments.first} failed: #{stderr}" unless status.success?

        stdout
      end
      begin
        tmux.call("-f", "/dev/null", "new-session", "-d", "-s", "verify", "-n", "editor",
          "-x", "100", "-y", "30", "sleep 3600")
        if config
          path = File.join(directory, "test.conf")
          File.write(path, config)
          tmux.call("source-file", path)
        end
        yield tmux
      ensure
        Open3.capture3("tmux", "-S", socket, "kill-server")
      end
    end
  end

  # What tmux renders for `format` in the throwaway server.
  def render(tmux, format, target: "verify:editor")
    source = format.respond_to?(:to_tmux) ? format.to_tmux : format
    tmux.call("display-message", "-p", "-t", target, source).chomp
  end

  # Exercise the same source-capture path as the CLI, with a real filename for
  # diagnostics and helper scoping.
  def load_source(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "config.rb")
      File.write(path, source)
      Tmux.load_file(path)
    end
  end
end

Minitest::Test.include(TmuxTestHelper)
