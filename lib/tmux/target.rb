# frozen_string_literal: true

require "open3"
require "tmpdir"
require "did_you_mean"

module Tmux
  # A target is an executable, not a guessed list keyed by a version string.
  # Each discovered catalog belongs to the exact binary (including its stat),
  # so changing PATH or replacing a binary cannot reuse another build's data.
  class Target
    CONTEXT_KEY = :tmux_rb_target

    def self.current = Thread.current[CONTEXT_KEY] || for_executable("tmux")

    def self.with(target)
      previous = Thread.current[CONTEXT_KEY]
      Thread.current[CONTEXT_KEY] = target
      yield
    ensure
      Thread.current[CONTEXT_KEY] = previous
    end

    def self.for_executable(executable)
      return executable if executable.is_a?(self)

      name = executable.to_s
      path = if name.include?(File::SEPARATOR)
        File.expand_path(name)
      else
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.expand_path(name, dir) }
          .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
      end
      unless path && File.file?(path) && File.executable?(path)
        raise Error, "tmux executable not found: #{name.inspect}; install tmux or select it with --tmux PATH"
      end

      real = File.realpath(path)
      stat = File.stat(real)
      key = [real, stat.ino, stat.size, stat.mtime, stat.ctime]
      @targets ||= {}
      @targets[key] ||= new(real)
    end

    attr_reader :executable

    def initialize(executable)
      @executable = executable
    end

    def version
      @version ||= begin
        output = run!("-V").strip
        unless output.start_with?("tmux ") && output.length > 5
          raise Error, "not a tmux executable: #{executable.inspect} (-V returned #{output.inspect})"
        end
        output.delete_prefix("tmux ")
      end
    end

    def at_least?(threshold)
      actual = version.match(/(\d+)\.(\d+)/)
      return true unless actual # Match the DSL's treatment of unnumbered master builds.

      expected = threshold.split(".").map(&:to_i)
      (actual.captures.map(&:to_i) <=> expected) >= 0
    end

    def catalog
      version
      @catalog ||= isolated do |socket|
        scopes = {global: "-g", server: "-s", window: "-gw"}.to_h do |scope, flags|
          stdout, _stderr, status = run("-S", socket, "show-options", "#{flags}H")
          stdout = run!("-S", socket, "show-options", flags) unless status.success?
          [scope, OptionCatalog.parse(stdout)]
        end
        OptionCatalog.new(self, scopes)
      end
    end

    # Resolve aliases using tmux itself. This also handles aliases introduced by
    # newer builds, without maintaining a second hardcoded compatibility list.
    def canonical_name(name)
      isolated do |socket|
        stdout, _stderr, status = run("-S", socket, "show-options", "-g", name)
        next unless status.success?

        stdout.lines.first&.split&.first&.sub(/\[\d+\]\z/, "")
      end
    end

    def run(*arguments) = Open3.capture3(executable, *arguments)

    def run!(*arguments)
      stdout, stderr, status = run(*arguments)
      raise Error, "tmux #{version_label} #{arguments.first} failed: #{stderr.strip}" unless status.success?

      stdout
    end

    def isolated
      Dir.mktmpdir("tmux-rb-options") do |directory|
        socket = File.join(directory, "tmux.sock")
        begin
          run!("-S", socket, "-f", "/dev/null", "new-session", "-d", "-s", "tmux_rb_options", "sleep 3600")
          yield socket
        ensure
          run("-S", socket, "kill-server")
        end
      end
    end

    private

    def version_label = @version || executable
  end

  class OptionCatalog
    def self.parse(output)
      output.each_line.each_with_object({}) do |line, entries|
        token, value = line.strip.split(/\s+/, 2)
        next unless token&.match?(/\A[a-z0-9][a-z0-9-]*(?:\[\d+\])?\z/)

        name = token.sub(/\[\d+\]\z/, "")
        entries[name] = {array: token.include?("[") || value.nil?}.freeze
      end.freeze
    end

    attr_reader :target, :scopes

    def initialize(target, scopes)
      @target = target
      @scopes = scopes.freeze
      @aliases = {}
    end

    def validate!(name, scope: nil)
      return name if name.start_with?("@") && name.length > 1

      match = name.match(/\A([a-z0-9][a-z0-9-]*)(?:\[(\d+)\])?\z/)
      unknown!(name) unless match
      base, index = match.captures
      canonical = canonical(base)
      unknown!(name) unless canonical
      owners = scopes.keys.select { |owner| scopes.fetch(owner).key?(canonical) }
      if scope && !owners.include?(scope)
        raise Error, "#{name.inspect} is not a #{scope} option in tmux #{target.version}; " \
          "use #{owners.first}.#{canonical.tr('-', '_')}"
      end
      if index && !scopes.fetch(owners.first).fetch(canonical).fetch(:array)
        raise Error, "#{base.inspect} is not an array option in tmux #{target.version}"
      end
      name
    end

    private

    def canonical(base)
      return base if scopes.values.any? { |entries| entries.key?(base) }
      return @aliases[base] if @aliases.key?(base)

      resolved = target.canonical_name(base)
      @aliases[base] = if resolved && scopes.values.any? { |entries| entries.key?(resolved) }
        resolved
      end
    end

    def unknown!(name)
      suggestions = DidYouMean::SpellChecker.new(dictionary: scopes.values.flat_map(&:keys).uniq).correct(name)
      hint = suggestions.empty? ? "" : "; did you mean #{suggestions.first.inspect}?"
      raise Error, "unknown option #{name.inspect} for tmux #{target.version}#{hint}"
    end
  end

  # Validate both shell branches (either may run), but only the applicable
  # version branch. Imports are rechecked against the destination's target.
  class OptionValidator
    def initialize(target) = @target = target

    def validate(nodes)
      nodes.each do |node|
        case node
        when ConfigNode::SetOption, ConfigNode::UnsetOption
          next if node.name.start_with?("@") && node.name.length > 1

          @target.catalog.validate!(node.name, scope: node.scope)
        when ConfigNode::IfShell
          validate(node.success)
          validate(node.failure)
        when ConfigNode::Condition
          active = @target.at_least?(node.version)
          active = !active if node.direction == :below
          validate(active ? node.body : node.otherwise)
        end
      end
    end
  end

  private_constant :Target, :OptionCatalog, :OptionValidator
end
