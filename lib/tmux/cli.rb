# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "securerandom"
require "tempfile"
require "tmpdir"
require_relative "../tmux"

module Tmux
  # The tmux.rb command (also installed as tmux_rb). #run returns an exit status and never exits the
  # process, so it is safe to call from other Ruby code.
  class CLI
    def self.run(arguments, stdout: $stdout, stderr: $stderr)
      new(stdout:, stderr:).run(arguments)
    end

    def initialize(stdout:, stderr:)
      @stdout = stdout
      @stderr = stderr
      @tmux_executable = "tmux"
      @plugin_path = []
    end

    def run(arguments)
      arguments = arguments.dup
      command = arguments.shift
      case command
      when "build" then build(arguments)
      when "check" then check(arguments)
      when "diff" then diff(arguments)
      when "load" then load_config(arguments)
      when "-v", "--version", "version"
        @stdout.puts version_line
        0
      when "-h", "--help", "help"
        @stdout.puts usage
        0
      else
        @stderr.puts "tmux.rb: unknown command: #{command}" if command
        @stderr.puts usage
        2
      end
    rescue OptionParser::ParseError, Error, SystemCallError => error
      @stderr.puts "tmux.rb: #{error.message}"
      1
    end

    private

    def build(arguments)
      output = nil
      return 0 unless parse_options(arguments, "build CONFIG.rb [--output TMUX.conf]") do |opts|
        opts.on("-o", "--output PATH", "Write atomically to PATH instead of stdout") { |path| output = path }
      end

      rendered = render(require_source!(arguments))
      output ? atomic_write(output, rendered) : @stdout.write(rendered)
      0
    end

    def check(arguments)
      return 0 unless parse_options(arguments, "check CONFIG.rb")

      source = require_source!(arguments)
      object = load_source(source)
      if object.is_a?(Format)
        @stdout.puts "#{source}: compiled to a format; formats are only parsed by tmux when it renders them"
        return 0
      end

      validate_with_tmux(object.to_tmux, target: object.target)
      @stdout.puts "#{source}: tmux parsed the generated configuration " \
        "(option names validated; commands and values were not applied)"
      0
    end

    def diff(arguments)
      return 0 unless parse_options(arguments, "diff CONFIG.rb TMUX.conf")

      source, target = arguments
      raise Error, "usage: tmux.rb diff CONFIG.rb TMUX.conf" unless source && target && arguments.size == 2

      Tempfile.create(["tmux_rb", ".conf"]) do |file|
        file.write(render(source))
        file.flush
        stdout, stderr, status = Open3.capture3("diff", "-u", target, file.path)
        @stdout.write(stdout)
        @stderr.write(stderr)
        return status.exitstatus || 2
      end
    end

    def load_config(arguments)
      target = []
      return 0 unless parse_options(arguments, "load [-S SOCKET | -L NAME] CONFIG.rb") do |opts|
        opts.on("-S", "--socket PATH", "Load into the server at this socket path") { |path| target = ["-S", path] }
        opts.on("-L", "--socket-name NAME", "Load into the server with this socket name") { |name| target = ["-L", name] }
      end

      source = require_source!(arguments)
      object = load_source(source)
      raise Error, "#{source} must evaluate to a Tmux::Config" unless object.is_a?(Config)

      server_version = object.target.run!(*target, "display-message", "-p", '#{version}').strip
      unless server_version == object.target.version
        raise Error, "destination server is tmux #{server_version}, but this config targets tmux #{object.target.version}; " \
          "select a matching executable with --tmux PATH"
      end

      Tempfile.create(["tmux_rb-load", ".conf"]) do |file|
        file.write(object.to_tmux)
        file.flush
        stdout, stderr, status = object.target.run(*target, "source-file", file.path)
        raise Error, "tmux rejected generated config:\n#{stderr}#{stdout}" unless status.success?
      end
      0
    end

    # Parses a subcommand's options. Returns false after printing help or the
    # version, so the caller can return 0 without exiting the process.
    def parse_options(arguments, synopsis)
      early = nil
      parser = OptionParser.new do |opts|
        opts.banner = "usage: tmux.rb #{synopsis}"
        yield opts if block_given?
        opts.on("--tmux PATH", "Target this tmux executable (default: tmux on PATH)") { |path| @tmux_executable = path }
        opts.on("--plugin-path DIR", "Look for plugins in DIR (a plugin or a directory of them) first; repeatable") do |dir|
          @plugin_path << dir
        end
        opts.on("-h", "--help", "Show this help") { early = :help }
        opts.on("--version", "Show the tmux.rb version") { early = :version }
      end
      parser.parse!(arguments)
      @stdout.puts(early == :help ? parser.help : version_line) if early
      early.nil?
    end

    def require_source!(arguments)
      source = arguments.shift
      raise Error, "expected exactly one Ruby configuration path" unless source && arguments.empty?

      source
    end

    def render(path) = load_source(path).to_tmux

    # Errors raised while the configuration runs are reported with the line
    # in the configuration file that raised them.
    def load_source(path)
      Tmux.load_file(path, tmux: @tmux_executable, plugin_path: @plugin_path)
    rescue SyntaxError => error
      raise Error, error.message
    rescue StandardError, ScriptError => error
      location = location_in(error, File.expand_path(path))
      raise if location.nil? && (error.is_a?(Error) || error.is_a?(SystemCallError))

      raise Error, "#{location || path}: #{error.message} (#{error.class})#{plugin_hint(error)}"
    end

    # For a failed require: where tmux.rb looked for plugins.
    def plugin_hint(error)
      return "" unless error.is_a?(LoadError)

      "\n(plugins are looked up in #{Plugins.search_path(extra: @plugin_path).join(", ")}; " \
        "add others with --plugin-path or TMUX_RB_PLUGIN_PATH. " \
        "A plugin is found by name when it ships lib/<its directory name>.rb)"
    end

    # The innermost backtrace frame inside the configuration file itself.
    def location_in(error, path)
      frame = error.backtrace_locations&.find { |location| location.absolute_path == path || location.path == path }
      frame && "#{frame.path}:#{frame.lineno}"
    end

    # Writes beside the real destination, then renames over it, so readers
    # never see a partial file. A symlinked destination (e.g. ~/.tmux.conf
    # pointing into a dotfiles repository) is followed rather than replaced,
    # and an existing file keeps its permissions.
    def atomic_write(path, contents)
      destination = resolve_symlinks(path)
      temporary = nil
      FileUtils.mkdir_p(File.dirname(destination))
      mode = File.exist?(destination) ? File.stat(destination).mode & 0o7777 : nil
      temporary = "#{destination}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, "w") do |file|
        file.write(contents)
        file.fsync
      end
      File.chmod(mode, temporary) if mode
      File.rename(temporary, destination)
    ensure
      FileUtils.rm_f(temporary) if temporary
    end

    def resolve_symlinks(path)
      target = File.expand_path(path)
      40.times do
        return target unless File.symlink?(target)

        target = File.expand_path(File.readlink(target), File.dirname(target))
      end
      raise Error, "too many levels of symbolic links: #{path}"
    end

    # The throwaway server's socket lives in a temporary directory, because
    # tmux leaves its socket file behind when the server is killed, and its
    # session runs `sleep` so the user's shell and rc files never start.
    def validate_with_tmux(contents, target:)
      Dir.mktmpdir("tmux_rb-check") do |directory|
        config = File.join(directory, "check.conf")
        File.write(config, contents)
        target.isolated do |socket|
          stdout, stderr, status = target.run("-S", socket, "source-file", "-n", config)
          raise Error, "tmux rejected generated config:\n#{stderr}#{stdout}" unless status.success?
        end
      end
    end

    def version_line = "tmux.rb #{VERSION}"

    def usage
      <<~TEXT
        usage:
          tmux.rb build CONFIG.rb [--output TMUX.conf]
          tmux.rb check CONFIG.rb
          tmux.rb diff CONFIG.rb TMUX.conf
          tmux.rb load [-S SOCKET | -L NAME] CONFIG.rb
          tmux.rb --version

        Run `tmux.rb COMMAND --help` for a command's options.
        All commands accept --tmux PATH to select the target tmux executable.
      TEXT
    end
  end
end
