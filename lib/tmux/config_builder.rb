# frozen_string_literal: true

module Tmux
  # The context of a Tmux.configure block. Every DSL method returns the
  # builder (conditionals return a handle for `.else`, and `bind(key)` a
  # BindingChain), so calls can be chained.
  class ConfigBuilder
    include Evaluation

    attr_reader :target

    def initialize(target: Target.current)
      @target = target
      @nodes = []
      @else_filled = {}
      @conditional_states = {}
      @open_bindings = []
    end

    def switch(cases) = Tmux.switch(cases)
    def shell(command, background: false) = Tmux.shell(command, background:)

    def blank
      @nodes << ConfigNode::Blank.new
      self
    end

    # Verbatim tmux commands, one node per line. A line ending in "\\" keeps
    # the next line in the same command, matching tmux's line continuation.
    def raw(command)
      pending = nil
      command.to_s.each_line(chomp: true) do |line|
        pending = pending ? "#{pending}\n#{line}" : line
        next if pending[/\\*\z/].length.odd?

        @nodes << (pending.empty? ? ConfigNode::Blank.new : ConfigNode::Command.new(pending))
        pending = nil
      end
      @nodes << ConfigNode::Command.new(pending) if pending
      self
    end

    # Scoped options are generated from the selected target's complete catalog.
    def global = option_root(:global)
    def server = option_root(:server)
    def window = option_root(:window)

    def environment(name, value)
      raw "set-environment -g #{ConfigCompiler.quote(name)} #{ConfigCompiler.quote(value)}"
    end

    # Build a reusable tmux command sequence. This makes ordinary Ruby helper
    # methods composable with bind, e.g. `bind "r", reload_config`.
    def commands(&block)
      builder = CommandBuilder.new
      Evaluation.run(builder, block)
      builder.build
    end

    # A reusable command sequence that recompiles and loads a Ruby config, with
    # an optional success message. Intended to be returned from ordinary Ruby
    # helper methods and passed directly to #bind.
    def load_config(path, executable: "tmux.rb", message: nil)
      commands do
        load_config(path, executable:)
        display_message message if message
      end
    end

    def unbind(key, table: nil, no_prefix: false)
      raise Error, "unbind cannot combine table: and no_prefix:" if table && no_prefix

      raw [
        "unbind-key",
        ("-n" if no_prefix),
        ("-T #{ConfigCompiler.quote(table)}" if table),
        ConfigCompiler.quote(key)
      ].compact.join(" ")
    end

    # With neither a command nor a block, bind returns a chain that adds each
    # command to the binding: `bind("-").split(:vertical).cwd(:current)`.
    def bind(key, command = nil, table: nil, repeat: false, no_prefix: false, note: nil, &block)
      raise Error, "bind cannot combine table: and no_prefix:" if table && no_prefix
      raise Error, "bind accepts either a command or a block, not both" if command && block

      parts = ["bind-key"]
      parts << "-r" if repeat
      parts << "-n" if no_prefix
      parts.concat(["-N", ConfigCompiler.quote(note)]) if note
      parts.concat(["-T", ConfigCompiler.quote(table)]) if table
      parts << ConfigCompiler.quote(key)
      prefix = parts.join(" ")

      unless command || block
        chain = BindingChain.new(key, prefix, @nodes, @nodes.size)
        @nodes << ConfigNode::Blank.new # replaced by the chain's first command
        @open_bindings << chain
        return chain
      end

      command = commands(&block) if block
      raw "#{prefix} #{command}"
    end

    # source-file; `quiet: true` (-q) skips a missing file without an error.
    def source(path, quiet: false) = raw("source-file#{' -q' if quiet} #{ConfigCompiler.quote(path)}")

    def run_shell(command, background: false)
      raw "run-shell#{' -b' if background} #{ConfigCompiler.quote(command)}"
    end

    # Runtime configuration branches, using either a tmux expression or a
    # deferred shell check. Branches remain native tmux command blocks.
    def if?(condition, background: false, &block)
      node = conditional_branch(condition, block, background:)
      index = @nodes.size
      @nodes << node
      @conditional_states[index] = [node]
      @else_filled[index] = false
      ConfigConditional.new(self, index)
    end

    def fill_elsif(index, condition, block, background: false)
      open_conditional(index, ".elsif?")
      branch = conditional_branch(condition, block, background:)
      @conditional_states.fetch(index) << branch
      rebuild_conditional(index, [])
    end

    def fill_else(index, block)
      node = @nodes[index]
      unless (node.is_a?(ConfigNode::IfShell) || node.is_a?(ConfigNode::Condition)) && @else_filled.key?(index)
        raise Error, ".else must directly follow the if?, tmux_from, or tmux_below it belongs to"
      end
      raise Error, "this conditional already has an else branch" if @else_filled[index]

      otherwise = capture(block)
      @else_filled[index] = true
      if node.is_a?(ConfigNode::IfShell)
        rebuild_conditional(index, otherwise)
      else
        @nodes[index] = node.with(otherwise: otherwise)
      end
      self
    end

    # Version-gated config: the block applies only when the running tmux server
    # is older than / at least `version` ("major.minor"). Compiles to a %if on
    # tmux's own #{version}, so no shell runs and no tmux binary on PATH is
    # consulted.
    def tmux_below(version, &block) = version_gate(:below, version, block)
    def tmux_from(version, &block) = version_gate(:from, version, block)

    def append(config)
      @nodes.concat(config.nodes)
      self
    end

    # Import another tmux config object into this config. `component` is anything
    # implementing #to_config (returning a Tmux::Config) — e.g. a plugin's Ruby
    # package. Splices its nodes in call order.
    def use(component) = append(component.to_config)

    def build
      if (open = @open_bindings.find(&:empty?))
        raise Error, "bind #{open.key.inspect} has no command: chain one, such as .split(:vertical), or pass a command or block"
      end

      Config.new(@nodes, target: target).validate!
    end

    private

    def conditional_branch(condition, block, background:)
      if condition.is_a?(ShellCondition)
        test = condition.command
        background ||= condition.background
        format = false
      else
        test = Tmux.expression(condition).source
        format = true
      end
      ConfigNode::IfShell.new(test, capture(block), [], format, background)
    end

    def open_conditional(index, method)
      unless @nodes[index].is_a?(ConfigNode::IfShell) && @conditional_states.key?(index)
        raise Error, "#{method} must follow the if? it belongs to"
      end
      raise Error, "this conditional already has an else branch" if @else_filled[index]
    end

    def rebuild_conditional(index, otherwise)
      @nodes[index] = @conditional_states.fetch(index).reverse_each.reduce(otherwise) do |failure, branch|
        [branch.with(failure:)]
      end.first
    end

    def write_option(name, value, scope:, append: false, expand: true)
      @nodes << ConfigNode::SetOption.new(normalize_option(name), value, scope, append, expand)
    end

    def remove_option(name, scope:)
      @nodes << ConfigNode::UnsetOption.new(normalize_option(name), scope)
    end

    def option_root(scope)
      @option_roots ||= {}
      @option_roots[scope] ||= OptionNode.root(self, scope)
    end

    # Runs a branch block on this same builder with a fresh node buffer, so
    # helper methods and instance variables stay visible in nested blocks.
    def capture(block)
      return [] unless block

      saved = [@nodes, @else_filled, @conditional_states]
      @nodes = []
      @else_filled = {}
      @conditional_states = {}
      evaluate(block)
      @nodes
    ensure
      @nodes, @else_filled, @conditional_states = saved if saved
    end

    def normalize_option(name)
      value = name.to_s
      value.start_with?("@") ? value : value.tr("_", "-")
    end

    def version_gate(direction, version, block)
      @nodes << ConfigNode::Condition.new(version_condition(direction, version), capture(block), [], version, direction)
      @else_filled[@nodes.size - 1] = false
      Else.new(self, @nodes.size - 1)
    end

    # #{version} as major * 1000 + minor, so 3.10 sorts after 3.9 and "3.5a",
    # "next-3.6", or "openbsd-7.5" compare by their numbers. A version without
    # a number (a "master" build) counts as newest.
    VERSION_NUMBER = '#{?#{m/r:[0-9]+[.][0-9]+,#{version}},' \
      '#{e|+:#{e|*:#{s/^[^0-9]*([0-9]+)[.]([0-9]+).*$/\1/:version},1000},' \
      '#{s/^[^0-9]*([0-9]+)[.]([0-9]+).*$/\2/:version}},999999}'

    # Thresholds from 3.2 compare numerically with #{e|...}. tmux before 3.2
    # expands that to empty, which reads as "not at least", so "below" is
    # written as its negation and stays correct there. Older thresholds compare
    # the version string, which orders every 3.x and 4.x release correctly.
    def version_condition(direction, version)
      match = version.to_s.match(/\A(\d+)\.(\d+)\z/)
      raise Error, "invalid tmux version: #{version.inspect} (expected \"major.minor\", e.g. \"3.2\")" unless match

      major, minor = match.captures.map(&:to_i)
      if major > 3 || (major == 3 && minor >= 2)
        at_least = "#{'#{'}e|>=:#{VERSION_NUMBER},#{major * 1000 + minor}}"
        direction == :from ? at_least : "#{'#{'}?#{at_least},0,1}"
      else
        "#{'#{'}#{direction == :from ? '>=' : '<'}:#{'#{'}version},#{major}.#{minor}}"
      end
    end
  end
end
