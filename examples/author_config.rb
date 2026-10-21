# frozen_string_literal: true

# The tmux.rb author's own tmux configuration, kept as a complete real-world
# example. It is tested in test/author_config_test.rb: the generated output is
# pinned in test/fixtures/author_config.conf and loaded into an isolated tmux
# server. It integrates with tmux-ai-attn
# (https://github.com/cosmicbuffalo/tmux-ai-attn), which marks windows where an
# AI agent needs attention, and with pmux (https://github.com/cosmicbuffalo/pmux),
# a sidebar for long-running processes and agents; without pmux installed, its
# options are simply never set.
#
#   tmux.rb build examples/author_config.rb --output ~/.tmux.conf

require "tmux"

Tmux.configure do
  # prefix + r recompiles this file and loads it into the running server.
  def reload_config
    load_config __FILE__, message: "Configuration reloaded"
  end

  color_palette_type = Data.define(
    :black,
    :white,
    :blue,
    :green,
    :orange,
    :purple,
    :bar,
    :tab,
    :between,
    :current,
    :copy
  )

  colors = color_palette_type.new(
    black: "#000000",
    white: "#ffffff",
    blue: "#5eaceb",
    green: "#6a9955",
    orange: "#ff8800",
    purple: "#c785c0",
    bar: "#1a1a19",
    tab: "#2d2d30",
    between: "#3a3a3a",
    current: "#4e4e4e",
    copy: "#1b2817"
  )

  # The four colors a window tab needs.
  window_colors_type = Data.define(:index_fg, :index_bg, :name_fg, :name_bg)

  inactive_window = window_colors_type.new(
    index_fg: colors.tab,
    index_bg: colors.blue,
    name_fg: colors.blue,
    name_bg: colors.tab
  )

  active_window = window_colors_type.new(
    index_fg: colors.black,
    index_bg: colors.orange,
    name_fg: colors.white,
    name_bg: colors.current
  )

  prefix = Tmux.client_prefix
  copy_mode = Tmux.pane_in_mode

  # Prefix/copy-mode indicator color, shared by both status bars.
  mode = Tmux.switch(prefix => colors.orange, copy_mode => colors.green, else: colors.tab)

  status_left = Tmux.format do
    right_segment(" ", bg: mode, fg: colors.tab, over: :default, p: 0)
  end

  # Paths under the home directory of whoever builds the config show as "~/".
  home = "#{Dir.home}/"

  zoomed = Tmux.window_zoomed_flag

  status_right = Tmux.format do
    if?(zoomed) do
      left_flag(
        "Z",
        bg: colors.white,
        fg: colors.black,
        attrs: :bold
      )
    end

    if?(copy_mode) do
      left_flag(
        Tmux.pane_mode,
        bg: colors.green,
        fg: colors.black
      )
    end

    left_segment(
      Tmux.pane_current_path.substitute(home, "~/"),
      bg: colors.tab,
      fg: colors.white,
    )

    left_segment(
      Tmux.pane_current_command,
      bg: colors.between,
      fg: colors.white,
    )

    left_segment(
      [Tmux.session_name, "@", Tmux.host],
      bg: colors.blue,
      fg: colors.black,
      attrs: :bold
    )

    # Mode indicator: a separator bevel and an end cap whose color reflects the
    # prefix/copy-mode state (mode is defined once, shared with status-left).
    left_segment(bg: colors.black, fg: colors.tab, p: 0)
    left_segment(" ", bg: mode, fg: colors.tab, p: 0)
  end

  active = Tmux.pane_active
  command = Tmux.pane_current_command
  current_path = Tmux.pane_current_path.substitute(home, "~/")
  shell = command.matches('^(bash|dash|fish|ksh|sh|tcsh|zsh)$')

  # Active pane tints the label and the index chip; inactive uses the muted palette.
  # While the pmux sidebar flashes a pane (cursor/pointer resting on the process
  # attached there) it toggles @pmux_flash_pane on/off, and the chip alternates
  # between the sidebar's accent and the muted tab color regardless of focus.
  # The accent is ANSI cyan, matching the sidebar's drag handle and its own
  # flashing row in the terminal's palette.
  pmux_flash_color = :cyan
  pane_flash = Tmux.user_option(:@pmux_flash_pane)
  label_fg = Tmux.switch(active => colors.orange, else: colors.white)
  chip_bg = Tmux.switch(
    (pane_flash == :on) => pmux_flash_color,
    (pane_flash == :off) => colors.tab,
    active => colors.orange,
    else: colors.tab
  )
  index_fg = Tmux.switch(
    (pane_flash == :on) => :colour235,
    (pane_flash == :off) => :white,
    active => :colour235,
    else: :white
  )
  border_label = Tmux.switch(shell => command, else: current_path)

  pane_border = Tmux.pane_border do
    left do
      style(fg: label_fg, p: 1) do
        append border_label
      end
    end
    right do
      chip(Tmux.pane_index, bg: chip_bg, fg: index_fg)
    end
  end

  # Core keys and navigation
  unbind "C-b"
  global.prefix = "C-s"
  bind "C-s", "send-prefix"
  bind "s", %q{split-window -v -c "#{pane_current_path}"}
  bind "v", %q{split-window -h -c "#{pane_current_path}"}
  bind "C-s", %q{split-window -v -c "#{pane_current_path}"}
  bind "C-v", %q{split-window -h -c "#{pane_current_path}"}
  bind '"', %q{split-window -c "#{pane_current_path}"}
  bind "%", %q{split-window -h -c "#{pane_current_path}"}
  bind "@", %q{split-window -h -c "#{pane_current_path}" -p 33 \; select-pane -L}

  {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}"
    bind "C-#{key}", "select-pane -#{direction}"
  end
  bind "<", "resize-pane -L 10", repeat: true
  bind ">", "resize-pane -R 10", repeat: true
  bind "-", "resize-pane -D 10", repeat: true
  bind "+", "resize-pane -U 10", repeat: true
  bind "=", "select-layout tiled"
  bind ":", "command-prompt"
  bind "C", "new-session"
  bind "L", "choose-session"
  bind "R", "move-window -r"
  bind "C-a", "last-window"
  bind "`", "last-window"
  bind "K", "confirm kill-server"
  bind "X", "confirm kill-window"
  bind "P", "choose-buffer -Z"

  window.mode_keys = :vi
  global.base_index = 1
  server.escape_time = 0
  global.history_limit = 10_000
  server.focus_events = true
  global.update_environment = "DISPLAY WINDOWID SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION"

  tmux_below "2.9" do
    global.status_bg = :default
    global.status_fg = :white
  end
  tmux_from "2.9" do
    global.status_style = "bg=terminal,fg=white"
  end

  # Status bar
  global.status.position = :top
  global.status.left.length = 100
  global.status.right.length = 100
  tmux_below "2.9" do
    global.status_left_bg = :default
    global.status_left_fg = :white
    global.status_left_attr = :none
  end
  tmux_from "2.9" do
    global.status_left_style = "bg=default,fg=white,none"
  end
  global.status.left = status_left
  global.status.right = status_right

  # Window tab: standard index/name plus the tmux-ai-attn segment, flash/phase
  # coloring, zoom parens, and a synchronize-panes marker. None of this belongs
  # in the generic library; it lives with the config that defines these user
  # options.
  window_tab = ->(colors) do
    state = Tmux.user_option(:@ai_attn_window_state)
    flash = Tmux.user_option(:@ai_attn_window_flash)
    phase = Tmux.user_option(:@ai_attn_flash_phase)
    # The pmux sidebar sets @pmux_flash_window while flashing a process that is
    # attached in another window: the same span ai-attn flashes (segment through
    # name), in the sidebar's cyan accent instead of ai-attn's yellow.
    pmux_flash = Tmux.user_option(:@pmux_flash_window) == :on
    zoomed = Tmux.window_zoomed_flag
    synchronized = Tmux.pane_synchronized

    Tmux.format do
      style(fg: colors.index_fg, bg: colors.index_bg, p: 1) do
        append Tmux.window_index
      end

      style fg: colors.name_fg, bg: colors.name_bg
      if?(pmux_flash) { style fg: :colour235, bg: pmux_flash_color }
      if?(!state) { text " " }
      # While the pmux flash is lit, drop the segment's own colors so its icon
      # (e.g. a green check) takes the flash's dark text color on cyan.
      if?(pmux_flash) do
        append Tmux.user_option(:@ai_attn_window_segment).substitute('#\[[^]]*\]', "")
      end.else do
        expand_option :@ai_attn_window_segment
      end
      # The segment ends with #[default] when ai-attn is not flashing, so the
      # pmux flash style is re-applied after it.
      if?(pmux_flash) do
        style fg: :colour235, bg: pmux_flash_color
      end.else do
        if?(!(flash && phase)) { style fg: colors.name_fg, bg: colors.name_bg }
      end

      if?(zoomed) do
        if?(!(flash && phase || pmux_flash)) { style fg: "colour44" }
        text "(", Tmux.window_name, ")"
      end.else do
        append Tmux.window_name
      end

      text " "
      if?(synchronized) do
        style fg: "brightred"
        text "(sync) "
      end
      reset_style
    end
  end

  window.status.format = window_tab.call(inactive_window)
  window.status.current.format = window_tab.call(active_window)
  tmux_below "2.9" do
    window.window_status_bg = :default
    window.window_status_fg = :white
    window.window_status_attr = :none
    window.window_status_current_attr = :none
  end
  tmux_from "2.9" do
    window.window_status_style = "bg=#{colors.tab},fg=#{colors.blue},none"
    window.window_status_current_style = "bg=#{colors.current},fg=#{colors.white},none"
  end

  tmux_below "2.9" do
    window.pane_border_bg = :default
    window.pane_border_fg = :colour238
    window.pane_active_border_bg = :default
    window.pane_active_border_fg = :colour214
  end
  tmux_from "2.9" do
    window.pane_border_style = "bg=default,fg=colour238"
    window.pane_active_border_style = "bg=default,fg=colour214"
  end

  server.default_terminal = "screen-256color"
  if?(shell("infocmp tmux-256color >/dev/null 2>&1")) do
    server.default_terminal = "tmux-256color"
  end.else do
    server.default_terminal = "screen-256color"
  end
  server.terminal_overrides << ',xterm*:sitm=\E[3m'

  # Mouse compatibility and reload
  tmux_from "2.1" do
    global.mouse = false
  end
  tmux_below "2.1" do
    window.mode_mouse = false
    global.mouse_resize_pane = false
    global.mouse_select_pane = false
    global.mouse_select_window = false
  end
  tmux_below "2.1" do
    bind "m", "set -g mode-mouse on \\; set -g -T prefixmouse-resize-pane on \\; set -g mouse-select-pane on \\; set -g mouse-select-window on \\; display 'Mouse: ON'"
    bind "M", "set -g mode-mouse off \\; set -g mouse-resize-pane off \\; set -g mouse-select-pane off \\; set -g mouse-select-window off \\; display 'Mouse: OFF'"
  end
  tmux_from "2.1" do
    bind "m", "set -g mouse on \\; display 'Mouse: ON'"
    bind "M", "set -g mouse off \\; display 'Mouse: OFF'"
  end
  bind "r", reload_config

  bind "N", %q{command-prompt "new-window -n '%%' -c '#{pane_current_path}'"}
  bind "c", %q{new-window -c '#{pane_current_path}'}
  bind "B", %q{confirm-before -p "Change prefix to C-b?" 'set -g prefix ^b'}
  bind "A", %q{confirm-before -p "Change prefix to C-a?" 'set -g prefix ^a'}
  bind "F", %q{confirm-before -p "Change prefix to C-s?" 'set -g prefix ^s'}
  bind "S", %q{command-prompt -p 'save history to filename:' -I '/tmp/tmux.history' 'capture-pane -S -32768 ; save-buffer %1 ; delete-buffer'}

  # Personal overrides
  bind "|", %q{split-window -h -c "#{pane_current_path}"}
  bind "-", %q{split-window -v -c "#{pane_current_path}"}
  bind "e", %q{run-shell -b '"$HOME/.local/bin/pmux" equalize-panes "#{pane_id}" --socket "#{socket_path}"'}
  bind "E", "select-layout even-vertical"
  bind "v", "send-keys -X begin-selection", table: "copy-mode-vi"
  bind "C-v", "send-keys -X rectangle-toggle", table: "copy-mode-vi"
  bind "C-v", "send-keys -X rectangle-toggle", table: "copy-mode"
  bind "y", "send-keys -X copy-selection-and-cancel", table: "copy-mode-vi"

  window.pane_base_index = 1
  global.renumber_windows = true

  %w[
    tmux-plugins/tpm
    tmux-plugins/tmux-pain-control
    tmux-plugins/tmux-sensible
    tmux-plugins/tmux-logging
    christoomey/vim-tmux-navigator
    jimeh/tmuxifier
    tmux-plugins/tmux-yank
    alexwforsythe/tmux-which-key
    tmux-plugins/tmux-resurrect
    cosmicbuffalo/tmux-ai-attn
  ].each { |plugin| global[:@plugin] = plugin }

  global[:@ai_attn_flash_multiplier] = 8
  global[:@ai_attn_color_text_fg] = :default
  global[:@ai_attn_seen_flash_seconds] = 30
  global["@resurrect-save"] = "Z"
  global["@resurrect-restore"] = "R"
  global[:@yank_action] = "copy-pipe-no-clear"

  server.set_clipboard = true
  server.terminal_overrides << ",*:clipboard:external"
  global.mouse = true
  window.mode_keys = :vi
  window.xterm_keys = true
  server.default_terminal = "xterm-256color"

  # Enable 24-bit (truecolor) passthrough so RGB colors survive the nested
  # setup (local truecolor terminal <- this outer tmux <- inner pmux tmux).
  server.terminal_features << ",*:RGB"

  window.pane.active_border.style = {fg: colors.orange}
  window.pane.border.style = {fg: colors.tab}
  window.pane.border.lines = :heavy
  window.pane.border.status = :top
  window.pane.border.format = pane_border
  window.style = "bg=colour236"
  window.active_style = "bg=colour234"
  global.message.style = {bg: colors.tab, fg: :white}
  global.message.command_style = {bg: :colour239, fg: :colour223}
  tmux_below("3.8") do
    global.display_panes.active_colour = colors.orange
    global.display_panes.colour = colors.blue
  end.else do
    window.display_panes.active_colour = colors.orange
    window.display_panes.colour = colors.blue
  end
  window.mode_style = {bg: colors.copy}
  window.status.bell_style = {bg: colors.orange, fg: :colour235}

  # Plugins and integrations
  run_shell "~/.tmux/plugins/tpm/tpm"
  source "~/.config/pmux/outer-tmux.conf", quiet: true
  if?(shell("test -f /usr/local/bin/reattach-to-user-namespace")) do
    global.default_command = "reattach-to-user-namespace -l zsh"
  end
end
