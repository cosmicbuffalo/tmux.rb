# frozen_string_literal: true

require "shellwords"

module Tmux
  class MenuBuilder
    def initialize = @entries = []

    def item(label, key:, command: nil, &block)
      raise Error, "menu item accepts either a command or a block, not both" if command && block

      if block
        builder = CommandBuilder.new
        Evaluation.run(builder, block)
        command = builder.build
      end
      raise Error, "menu item requires a command or block" unless command

      @entries << [label.to_s, key.to_s, command.to_s]
      self
    end

    def separator
      @entries << [""]
      self
    end

    def arguments = @entries.flatten
  end

  # Builds the command list attached to a key binding. Commands are kept as
  # separate entries until the binding is compiled, so callers never write tmux
  # command separators or quote command arguments by hand.
  class CommandBuilder
    # A command built by one of the named helpers below, kept in parts so a
    # modifier such as #cwd can still add a flag before it compiles.
    Typed = Struct.new(:name, :flags) do
      def to_s = [name, *flags].join(" ")
    end
    private_constant :Typed

    # tmux's own names: a vertical split (-v) stacks the new pane below, a
    # horizontal one (-h) puts it to the right. :v and :h are shorthand.
    SPLIT_DIRECTIONS = { vertical: "-v", v: "-v", horizontal: "-h", h: "-h" }.freeze
    PANE_DIRECTIONS = { left: "-L", right: "-R", up: "-U", down: "-D" }.freeze
    CWD_COMMANDS = %w[split-window new-window].freeze
    private_constant :SPLIT_DIRECTIONS, :PANE_DIRECTIONS, :CWD_COMMANDS

    def initialize = @commands = []

    # Any tmux command. Arguments are quoted for you; tmux expands $VARIABLES
    # and a leading ~ in them unless `expand: false` is passed.
    def command(name, *arguments, expand: true)
      command_name = normalize(name)
      parts = [command_name, *arguments.map { |argument| ConfigCompiler.quote(argument, expand:) }]
      @commands << parts.join(" ")
      self
    end

    def raw(command)
      @commands << command.to_s
      self
    end

    # split-window. `cwd:` starts the new pane in a directory; :current is the
    # active pane's directory. `size:` is lines/columns or a "30%" string.
    def split(direction, cwd: nil, size: nil)
      flag = SPLIT_DIRECTIONS.fetch(direction) do
        raise Error, "split direction must be :vertical (:v) or :horizontal (:h), not #{direction.inspect}"
      end
      flags = [flag]
      flags.concat(["-l", ConfigCompiler.quote(size)]) if size
      typed("split-window", flags, cwd:)
    end

    def new_window(name: nil, cwd: nil)
      flags = []
      flags.concat(["-n", ConfigCompiler.quote(name)]) if name
      typed("new-window", flags, cwd:)
    end

    # Start the previous command (split or new_window) in `directory`;
    # :current is the active pane's directory.
    def cwd(directory)
      last = @commands.last
      unless last.is_a?(Typed) && CWD_COMMANDS.include?(last.name)
        raise Error, "cwd must follow split or new_window"
      end
      raise Error, "#{last.name} already has a directory" if last.flags.include?("-c")

      last.flags.concat(["-c", ConfigCompiler.quote(directory == :current ? "\#{pane_current_path}" : directory)])
      self
    end

    # select-pane, by direction (:left, :right, :up, :down) and/or target.
    def select_pane(direction = nil, target: nil)
      parts = ["select-pane"]
      parts << pane_direction(direction) if direction
      parts.concat(["-t", ConfigCompiler.quote(target)]) if target
      @commands << parts.join(" ")
      self
    end

    # resize-pane by `amount` cells (tmux's default is 1) in a direction.
    def resize_pane(direction, amount = nil)
      @commands << ["resize-pane", pane_direction(direction), amount&.to_i].compact.join(" ")
      self
    end

    # Toggle the active pane's zoom (resize-pane -Z).
    def zoom = raw("resize-pane -Z")
    def kill_pane = raw("kill-pane")
    def kill_window = raw("kill-window")

    # source-file; `quiet: true` (-q) skips a missing file without an error.
    def source(path, quiet: false) = raw("source-file#{' -q' if quiet} #{ConfigCompiler.quote(path)}")

    # Send one copy-mode command (`send-keys -X`) to a pane. `count:` maps to
    # tmux's -N repeat count, used by actions such as scroll-up and scroll-down.
    def copy_mode(action, target: nil, count: nil)
      parts = ["send-keys"]
      parts.concat(["-t", ConfigCompiler.quote(target)]) if target
      parts << "-X"
      parts.concat(["-N", count.to_i]) if count
      parts << normalize(action)
      @commands << parts.join(" ")
      self
    end

    # Compile and load a Ruby configuration into the tmux server running this
    # command. The CLI renders through a temporary file, so callers only
    # maintain the .rb source. #{socket_path} expands when the binding runs, so
    # the load never follows a $TMUX that names some other (e.g. nested) server.
    def load_config(path, executable: "tmux.rb")
      load = Shellwords.join([executable, "load", "-S"])
      # expand: false: the shell, not tmux's parser, must see any "$" in the path.
      command :run_shell, "#{load} \"\#{socket_path}\" #{Shellwords.escape(path.to_s)}", expand: false
    end

    def display_message(message)
      command :display_message, message
    end

    def display_menu(title: nil, &block)
      menu = MenuBuilder.new
      Evaluation.run(menu, block)
      parts = ["display-menu"]
      parts.concat(["-T", ConfigCompiler.quote(title)]) if title
      parts.concat(menu.arguments.map { |argument| ConfigCompiler.quote(argument) })
      @commands << parts.join(" ")
      self
    end

    def empty? = @commands.empty?

    def build
      raise Error, "a command block must contain at least one command" if @commands.empty?

      @commands.map(&:to_s).join(" \\; ")
    end

    private

    def typed(name, flags, cwd: nil)
      @commands << Typed.new(name, flags)
      cwd ? self.cwd(cwd) : self
    end

    def pane_direction(direction)
      PANE_DIRECTIONS.fetch(direction) do
        raise Error, "pane direction must be :left, :right, :up, or :down, not #{direction.inspect}"
      end
    end

    def normalize(name) = name.to_s.tr("_", "-")
  end

  # What `bind(key)` returns without a command or block. Each CommandBuilder
  # method adds a command and rewrites the binding's configuration line, so the
  # chain can stop anywhere: bind("c").new_window.cwd(:current)
  class BindingChain
    attr_reader :key

    def initialize(key, prefix, nodes, index)
      @key = key
      @prefix = prefix
      @nodes = nodes
      @index = index
      @commands = CommandBuilder.new
    end

    def empty? = @commands.empty?

    (CommandBuilder.public_instance_methods(false) - %i[build empty?]).each do |name|
      define_method(name) do |*arguments, **options, &block|
        @commands.public_send(name, *arguments, **options, &block)
        @nodes[@index] = ConfigNode::Command.new("#{@prefix} #{@commands.build}")
        self
      end
    end
  end
end
