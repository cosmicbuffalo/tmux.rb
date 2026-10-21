# frozen_string_literal: true

require "rbconfig"
require "open3"
require "shellwords"
require "tmpdir"
require "tmux"

module OhMyTmux
  # Ruby-native implementation of the public Oh My Tmux profile. It keeps the
  # framework's settings model, but resolves it directly into a Tmux::Config
  # instead of encoding a shell program in commented tmux configuration.
  class Profile
    COLORS = {
      1 => "#080808", 2 => "#303030", 3 => "#8a8a8a",
      4 => "#00afff", 5 => "#ffff00", 6 => "#080808",
      7 => "#e4e4e4", 8 => "#080808", 9 => "#ffff00",
      10 => "#ff00af", 11 => "#5fff00", 12 => "#8a8a8a",
      13 => "#e4e4e4", 14 => "#080808", 15 => "#080808",
      16 => "#d70000", 17 => "#e4e4e4"
    }.freeze

    WINDOW_FORMAT =
      '#I #W#{?#{||:#{window_bell_flag},#{window_zoomed_flag}}, ,}' \
      '#{?window_bell_flag,!,}#{?window_zoomed_flag,Z,}'

    attr_accessor :preserve_stock_bindings, :new_session_prompt,
      :new_session_retain_current_path, :new_window_retain_current_path,
      :new_window_reconnect_ssh, :new_pane_retain_current_path,
      :new_pane_reconnect_ssh, :copy_to_os_clipboard

    def initialize(source_path:, output_path: "~/.tmux.conf")
      @source_path = File.expand_path(source_path)
      @output_path = File.expand_path(output_path)
      @preserve_stock_bindings = false
      @new_session_prompt = false
      @new_session_retain_current_path = false
      @new_window_retain_current_path = false
      @new_window_reconnect_ssh = false
      @new_pane_retain_current_path = true
      @new_pane_reconnect_ssh = false
      @copy_to_os_clipboard = false
      @plugins = []
      @colors = COLORS.dup
    end

    def color(number, value)
      @colors.fetch(number)
      @colors[number] = value
    end

    def plugin(repository)
      @plugins << repository
    end

    def to_config
      runtime = Shellwords.join([RbConfig.ruby, File.expand_path("runtime.rb", __dir__)])
      source = Shellwords.escape(@source_path)
      output = Shellwords.escape(@output_path)
      compiler = Shellwords.escape(ENV.fetch("TMUX_RB_EXECUTABLE", "tmux.rb"))
      c = @colors
      status_left = build_status_left
      status_right = build_status_right(runtime)
      window_status = build_window_status
      window_status_current = build_window_status_current
      mouse_menu, direct_mouse_menu = pane_menus(retain_path: @new_pane_retain_current_path)
      split_vertical = split_command(vertical: true, retain_path: @new_pane_retain_current_path)
      split_horizontal = split_command(vertical: false, retain_path: @new_pane_retain_current_path)
      stock_vertical = @new_pane_retain_current_path ?
        'split-window -c "#{pane_current_path}"' : "split-window"
      plugins = @plugins.dup

      Tmux.configure do
        # General behavior from the framework's native tmux section.
        server.default_terminal = "screen-256color"
        if?(shell('command infocmp -x tmux-256color >/dev/null 2>&1')) do
          server.default_terminal = "tmux-256color"
        end
        if?(shell(
          'case "$TERM" in screen-*|tmux-*) exit 1;; esac; ' \
          '[ "$COLORTERM" = truecolor ] || [ "$COLORTERM" = 24bit ] || ' \
          '[ "$(tput colors 2>/dev/null)" = 16777216 ]'
        )) do
          if?(Tmux.raw('#{>=:#{s/^[^0-9]+//:#{version}},3.2}')) do
            server.terminal_features << ",*256col*:RGB"
          end.else do
            server.terminal_overrides << ",*256col*:Tc"
          end
        end

        if?(Tmux.raw('#{>=:#{s/^[^0-9]+//:#{version}},3.2}')) do
          server.extended_keys = '#{?#{||:#{m/ri:mintty|iTerm|WezTerm|ghostty,#{TERM_PROGRAM}},#{!=:#{XTERM_VERSION},}},on,off}'
        end
        if?(Tmux.raw('#{>=:#{s/^[^0-9]+//:#{version}},3.3}')) do
          server.extended_keys = '#{?#{||:#{m/ri:mintty|iTerm|WezTerm|ghostty,#{TERM_PROGRAM}},#{!=:#{XTERM_VERSION},}},always,off}'
        end
        tmux_from("3.5") do
          server.extended_keys_format = "csi-u"
        end

        server.escape_time = 10
        global.repeat_time = 600
        server.focus_events = true
        global.prefix2 = "C-a"
        bind "C-a", "send-prefix -2"
        global.history_limit = 5000

        edit = "sh -c '_E=\${VISUAL:-\${EDITOR:-vim}}; " \
          "case \"\$_E\" in *vim*) \$_E -c \":set syntax=ruby\" #{source};; " \
          "*) \$_E #{source};; esac'"
        bind "e", "new-window -n tmux.rb #{edit}"
        bind "r", "run-shell \"#{compiler} build #{source} --output #{output}\"" \
          " \\; source-file #{output} \\; display-message \"Configuration reloaded\""

        global.base_index = 1
        bind "0", "select-window -t :=10"
        window.pane_base_index = 1
        window.automatic_rename = true
        global.renumber_windows = true
        global.set_titles = true
        tmux_below("3.8") { global.display_panes_time = 800 }
          .else { window.display_panes_time = 800 }
        global.display_time = 1000
        global.status_interval = 10
        bind "C-l", 'send-keys C-l \\; run-shell "sleep 0.2" \\; clear-history', no_prefix: true
        window.monitor_activity = true
        global.visual_activity = false

        bind "C-c", "new-session"
        bind "C-f", 'command-prompt -p "(find-session)" "switch-client -t %%"'
        bind "BTab", "switch-client -l"
        bind "-", split_vertical
        bind "_", split_horizontal
        {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
          bind key, "select-pane -#{direction}", repeat: true
        end
        bind ">", "swap-pane -D"
        bind "<", "swap-pane -U"
        bind "+", 'run-shell "' + runtime + %q{ maximize '#{session_name}' '#D'"}
        {H: "L", J: "D", K: "U", L: "R"}.each do |key, direction|
          bind key, "resize-pane -#{direction} 2", repeat: true
        end
        unbind "n"
        bind "C-h", "previous-window", repeat: true
        bind "C-l", "next-window", repeat: true
        bind "C-S-H", "swap-window -t -1 \\; select-window -t -1", repeat: true
        bind "C-S-L", "swap-window -t +1 \\; select-window -t +1", repeat: true
        bind "Tab", "last-window"
        bind "m", 'set-option -Fg mouse "#{?mouse,off,on}" \\; display-message "mouse: #{?mouse,on,off}"'
        bind "F", 'run-shell "' + runtime + %q{ fpp '#{pane_id}'"}
        bind "Enter", "copy-mode"
        bind "v", "send-keys -X begin-selection", table: "copy-mode-vi"
        bind "C-v", "send-keys -X rectangle-toggle", table: "copy-mode-vi"
        bind "y", "send-keys -X copy-selection-and-cancel", table: "copy-mode-vi"
        bind "Escape", "send-keys -X cancel", table: "copy-mode-vi"
        bind "H", "send-keys -X start-of-line", table: "copy-mode-vi"
        bind "L", "send-keys -X end-of-line", table: "copy-mode-vi"

        if?(shell("command -v xsel >/dev/null 2>&1", background: true)) do
          bind "y", 'run-shell -b "tmux save-buffer - | xsel -i -b"'
        end
        if?(shell("! command -v xsel >/dev/null 2>&1 && command -v xclip >/dev/null 2>&1", background: true)) do
          bind "y", 'run-shell -b "tmux save-buffer - | xclip -i -selection clipboard >/dev/null 2>&1"'
        end
        if?(shell('[ "$XDG_SESSION_TYPE" = wayland ] && command -v wl-copy >/dev/null 2>&1', background: true)) do
          bind "y", 'run-shell -b "tmux save-buffer - | wl-copy"'
        end
        if?(shell("command -v pbcopy >/dev/null 2>&1", background: true)) do
          bind "y", 'run-shell -b "tmux save-buffer - | pbcopy"'
        end
        if?(shell("command -v clip.exe >/dev/null 2>&1", background: true)) do
          bind "y", 'run-shell -b "tmux save-buffer - | clip.exe"'
        end

        bind "b", "list-buffers"
        bind "p", "paste-buffer -p"
        bind "P", "choose-buffer"

        # The framework rewrites the stock split bindings and mouse pane menu.
        bind '"', stock_vertical
        bind "%", split_horizontal
        bind "MouseDown3Pane", mouse_menu, table: :root
        bind "M-MouseDown3Pane", direct_mouse_menu, table: :root

        # Ruby-native theme materialization.
        window.window_style = "fg=default,bg=default"
        window.window_active_style = "default"
        window.pane_border_style = "fg=#{c[2]},bg=default"
        window.pane_active_border_style = 'fg=#{?pane_in_mode,' + c[9] + ',#{?synchronize-panes,' +
            c[16] + ",#{c[4]}}},bg=default"
        tmux_below("3.8") do
          global.display_panes_colour = c[4]
          global.display_panes_active_colour = c[4]
        end.else do
          window.display_panes_colour = c[4]
          window.display_panes_active_colour = c[4]
        end
        global.message_style = "fg=#{c[1]},bg=#{c[5]},bold"
        global.message_command_style = "fg=#{c[5]},bg=#{c[1]},bold"
        if?(Tmux.raw('#{>=:#{s/^[^0-9]+//:#{version}},3.7}')) do
          global.message_style = "fg=#{c[1]},bg=#{c[5]},bold,fill=#{c[5]}"
          global.message_command_style = "fg=#{c[5]},bg=#{c[1]},bold,fill=#{c[1]}"
        end
        window.mode_style = "fg=#{c[1]},bg=#{c[5]},bold"
        global.status_style = "fg=#{c[3]},bg=#{c[1]},none"
        global.status_left_style = "fg=#{c[3]},bg=#{c[1]},none"
        global.status_right_style = "fg=#{c[3]},bg=#{c[1]},none"
        window.window_status_style = "fg=#{c[3]},bg=#{c[1]},none"
        window.window_status_current_style = "fg=#{c[1]},bg=#{c[4]},bold"
        window.window_status_activity_style = "fg=default,bg=default,underscore"
        window.window_status_bell_style = "fg=#{c[5]},bg=default,blink,bold"
        window.window_status_last_style = "fg=#{c[4]},bg=#{c[2]},none"
        window.window_status_separator = " "
        window.clock_mode_colour = c[4]
        window.clock_mode_style = 24
        global.set_titles_string = "#h ❐ #S ● #I #W"
        window.window_status_format = window_status
        window.window_status_current_format = window_status_current
        global.status_left_length = 1000
        global.status_left = status_left
        global.status_right_length = 1000
        global.status_right = status_right

        run_shell "#{runtime} metrics-loop 60", background: true

        plugins.each { |repository| global[:@plugin] = repository }
        unless plugins.empty?
          run_shell '~/.tmux/plugins/tpm/tpm', background: true
        end
      end
    end

    private

    def split_command(vertical:, retain_path:)
      command = vertical ? "split-window -v" : "split-window -h"
      retain_path ? command + ' -c "#{pane_current_path}"' : command
    end

    def build_status_left
      c = @colors
      "#[fg=#{c[6]},bg=#{c[9]},bold] ❐ #S " \
        "#[fg=#{c[9]},bg=#{c[10]},none]" \
        "#[fg=#{c[7]},bg=#{c[10]},none] ↑" \
        '#{?@uptime_y, #{@uptime_y}y,}#{?@uptime_dy, #{@uptime_dy}d,}' \
        '#{?@uptime_h, #{@uptime_h}h,}#{?@uptime_m, #{@uptime_m}m,} ' \
        "#[fg=#{c[10]},bg=#{c[1]},none] "
    end

    def build_status_right(runtime)
      c = @colors
      username = "#(#{runtime} username " + %q{'#{pane_pid}' '#{b:pane_tty}' false '#D')}
      hostname = "#(#{runtime} hostname " + %q{'#{pane_pid}' '#{b:pane_tty}' false false '#h' '#D')}
      root = '#{?#{==:' + username + ',root},!,}'

      "#[fg=#{c[15]},bg=#{c[1]},none]#[fg=#{c[12]},bg=#{c[15]},none] " \
        '#[fg=none]#[bg=none]#[none]#{?client_prefix,⌨ ,  }#[default]' \
        "#[fg=#{c[12]},bg=#{c[15]},none]" \
        '#[fg=none]#[bg=none]#[none]#{?mouse,↗ ,  }#[default]' \
        "#[fg=#{c[12]},bg=#{c[15]},none]" \
        '#[fg=none]#[bg=none]#[none]#{?session_many_attached,⚇ ,}#[default]' \
        "#[fg=#{c[12]},bg=#{c[15]},none]" \
        '#[fg=none]#[bg=none]#[none]#{?pane_synchronized,⚏ ,}#[default]' \
        "#[fg=#{c[12]},bg=#{c[15]},none]" \
        '#{?@battery_status, #{@battery_status},}#{?@battery_bar, #{@battery_bar},}' \
        '#{?@battery_percentage, #{@battery_percentage},} ' \
        "#[fg=#{c[12]},bg=#{c[15]},none]| %R " \
        "#[fg=#{c[12]},bg=#{c[15]},none]| %d %b " \
        "#[fg=#{c[16]},bg=#{c[15]},none]" \
        "#[fg=#{c[13]},bg=#{c[16]},none] #{username}" \
        "#[fg=none]#[bg=none]#[bold,blink]#{root}#[default]" \
        "#[fg=#{c[13]},bg=#{c[16]},none] " \
        "#[fg=#{c[17]},bg=#{c[16]},none]" \
        "#[fg=#{c[14]},bg=#{c[17]},bold] #{hostname} "
    end

    def build_window_status_current
      c = @colors
      "#[fg=#{c[1]},bg=#{c[4]},none]" \
        "#[fg=#{c[1]},bg=#{c[4]},bold] #{WINDOW_FORMAT} " \
        "#[fg=#{c[4]},bg=#{c[1]}]"
    end

    def build_window_status
      c = @colors
      spacer = '#{?window_last_flag,#{?window_activity_flag,#{?window_bell_flag, , },' \
        '#{?window_bell_flag, , }},#{?window_activity_flag,#{?window_bell_flag,,},' \
        '#{?window_bell_flag,,}}}'

      [
        "#[fg=#{c[1]},bg=#{c[1]},none]",
        '#{?window_last_flag,#[bg=' + c[2] + '],}',
        '#{?window_activity_flag,,}#{?window_bell_flag,,}',
        "#[fg=#{c[3]},bg=#{c[1]},none]",
        '#{?window_last_flag,#[fg=' + c[4] + '],}',
        '#{?window_last_flag,#[bg=' + c[2] + '],}',
        '#{?window_activity_flag,,}#{?window_activity_flag,,}',
        '#{?window_bell_flag,#[fg=' + c[5] + '],}#{?window_bell_flag,,}',
        spacer,
        '#{?window_last_flag,#[none],}#{?window_last_flag,#[none],}',
        '#{?window_activity_flag,#[none],}#{?window_activity_flag,#[underscore],}',
        '#{?window_bell_flag,#[none],}#{?window_bell_flag,#[blink],}',
        '#{?window_bell_flag,#[bold],}',
        WINDOW_FORMAT,
        "#[none]",
        spacer,
        "#[fg=#{c[1]},bg=#{c[1]}]",
        '#{?window_last_flag,#[fg=' + c[2] + '],}',
        '#{?window_activity_flag,,}#{?window_bell_flag,,}'
      ].join
    end

    # Oh My Tmux rewrites tmux's own pane menu, which changes between tmux
    # releases, so the menu is read from the installed tmux's defaults, with
    # its split commands keeping the current path when configured to. Without
    # a usable tmux, the tmux 3.4 and 3.5 menu below stands in.
    # The MouseDown3Pane and M-MouseDown3Pane commands.
    def pane_menus(retain_path:)
      horizontal = retain_path ? 'split-window -h -c "#{pane_current_path}"' : "split-window -h"
      vertical = retain_path ? 'split-window -v -c "#{pane_current_path}"' : "split-window -v"
      defaults = default_pane_menus
      unless defaults
        menu = pane_menu(horizontal, vertical)
        return [menu, menu[/\{ (display-menu.*) \}\z/, 1]]
      end

      defaults.map do |command|
        command = command.gsub("{ split-window -h }", "{ #{horizontal} }").gsub("{ split-window -v }", "{ #{vertical} }")
        next command unless retain_path

        # Older tmux writes menu commands as quoted strings, nested one level
        # deeper in the direct menu; Oh My Tmux adds the path option there too.
        command.gsub(/(\\*")split-window (-[hv])\1/) { "#{$1}split-window -c '\#{pane_current_path}' #{$2}#{$1}" }
      end
    end

    def pane_menu(horizontal, vertical)
      prefix = 'if-shell -F -t = "#{||:#{mouse_any_flag},#{&&:#{pane_in_mode},' \
        '#{?#{m/r:(copy|view)-mode,#{pane_mode}},0,1}}}" ' \
        '{ select-pane -t = ; send-keys -M } '
      menu = 'display-menu -T "#[align=centre]#{pane_index} (#{pane_id})" -t = -x M -y M ' \
        '"#{?#{m/r:(copy|view)-mode,#{pane_mode}},Go To Top,}" < { send-keys -X history-top } ' \
        '"#{?#{m/r:(copy|view)-mode,#{pane_mode}},Go To Bottom,}" > { send-keys -X history-bottom } ' \
        "'' " \
        '"#{?mouse_word,Search For #[underscore]#{=/9/...:mouse_word},}" C-r ' \
        '{ if-shell -F "#{?#{m/r:(copy|view)-mode,#{pane_mode}},0,1}" "copy-mode -t=" ; send-keys -X -t = search-backward "#{q:mouse_word}" } ' \
        '"#{?mouse_word,Type #[underscore]#{=/9/...:mouse_word},}" C-y { copy-mode -q ; send-keys -l "#{q:mouse_word}" } ' \
        '"#{?mouse_word,Copy #[underscore]#{=/9/...:mouse_word},}" c { copy-mode -q ; set-buffer "#{q:mouse_word}" } ' \
        '"#{?mouse_line,Copy Line,}" l { copy-mode -q ; set-buffer "#{q:mouse_line}" } ' \
        "'' " \
        '"#{?mouse_hyperlink,Type #[underscore]#{=/9/...:mouse_hyperlink},}" C-h { copy-mode -q ; send-keys -l "#{q:mouse_hyperlink}" } ' \
        '"#{?mouse_hyperlink,Copy #[underscore]#{=/9/...:mouse_hyperlink},}" h { copy-mode -q ; set-buffer "#{q:mouse_hyperlink}" } ' \
        "'' \"Horizontal Split\" h { #{horizontal} } \"Vertical Split\" v { #{vertical} } '' " \
        '"#{?#{>:#{window_panes},1},,-}Swap Up" u { swap-pane -U } ' \
        '"#{?#{>:#{window_panes},1},,-}Swap Down" d { swap-pane -D } ' \
        '"#{?pane_marked_set,,-}Swap Marked" s { swap-pane } ' \
        "'' Kill X { kill-pane } Respawn R { respawn-pane -k } " \
        '"#{?pane_marked,Unmark,Mark}" m { select-pane -m } ' \
        '"#{?#{>:#{window_panes},1},,-}#{?window_zoomed_flag,Unzoom,Zoom}" z { resize-pane -Z }'
      prefix + "{ #{menu} }"
    end

    # The pane menu bindings of a tmux started with no configuration.
    def default_pane_menus
      Dir.mktmpdir("oh-my-tmux-defaults") do |directory|
        socket = File.join(directory, "tmux.sock")
        _out, _err, started = Open3.capture3("tmux", "-S", socket, "-f", "/dev/null", "new-session", "-d", "sleep 10")
        return nil unless started.success?

        # The whole table: tmux 3.7c lists nothing for a single named key.
        table, _err, listed = Open3.capture3("tmux", "-S", socket, "list-keys", "-T", "root")
        Open3.capture3("tmux", "-S", socket, "kill-server")
        return nil unless listed.success?

        commands = %w[MouseDown3Pane M-MouseDown3Pane].map do |key|
          table[/^bind-key\s+-T root\s+#{key}\s+(.*)$/, 1]
        end
        commands.all? ? commands : nil
      end
    rescue SystemCallError
      nil
    end
  end

  def self.configure(source_path:, output_path: "~/.tmux.conf", &block)
    profile = Profile.new(source_path:, output_path:)
    profile.instance_exec(&block) if block
    profile.to_config
  end
end
