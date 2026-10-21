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

    def select_pane(target: nil)
      parts = ["select-pane"]
      parts.concat(["-t", ConfigCompiler.quote(target)]) if target
      @commands << parts.join(" ")
      self
    end

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

    def build
      raise Error, "a command block must contain at least one command" if @commands.empty?

      @commands.join(" \\; ")
    end

    private

    def normalize(name) = name.to_s.tr("_", "-")
  end
end
