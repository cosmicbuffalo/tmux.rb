# frozen_string_literal: true

require "tmux"

# Port of tony/tmux-config's .tmux.conf.
Tmux.configure do
  def reload_config
    load_config "~/.config/tmux/tmux.rb", message: "Config reloaded..."
  end

  global.status.style = {bg: :colour235, fg: :colour136, attrs: :default}
  window.status.style = {fg: :colour244, bg: :default, attrs: :dim}
  window.status.current.style = {fg: :colour166, bg: :default, attrs: :bright}
  window.pane.border.style = {fg: :colour61}
  window.pane.active_border.style = {fg: :colour64}
  global.message.style = {bg: :colour235, fg: :colour166}
  tmux_below("3.8") do
    global.display_panes.active_colour = :colour33
    global.display_panes.colour = :colour166
  end.else do
    window.display_panes.active_colour = :colour33
    window.display_panes.colour = :colour166
  end
  window.clock.colour = :green

  global.status.interval = 1
  global.status.justify = :centre
  global.status.left.length = 20
  global.status.right.length = 140
  global.status_left = Tmux.format do
    style fg: :green
    append Tmux.host
    text " "
    style fg: :black
    text "• "
    style fg: :green, attrs: :bright
    command "uname -r | cut -c 1-6"
    reset_style
  end
  global.status_right = Tmux.format do
    style fg: :green, bg: :default, attrs: :bright
    command "tmux-mem-cpu-load"
    text " "
    style fg: :red, attrs: :dim, bg: :default
    command 'uptime | cut -f 4-5 -d " " | cut -f 1 -d ","'
    text " "
    style fg: :white, bg: :default
    strftime "%a%l:%M:%S %p"
    reset_style
    text " "
    style fg: :blue
    strftime "%Y-%m-%d"
  end

  global.prefix = "C-a"
  bind "C-a", "last-window"
  global.base_index = 1
  server.escape_time = 50
  window.aggressive_resize = true
  bind "a", "send-prefix"
  window.monitor_activity = true
  global.visual_activity = true
  window.mode_keys = :vi
  {
    "v" => :begin_selection,
    "y" => :copy_pipe_and_cancel,
    "C-v" => :rectangle_toggle,
  }.each do |key, action|
    bind key, table: "copy-mode-vi" do
      copy_mode action
    end
  end
  global.mouse = false

  {
    "c" => ["New window", "new-window", nil],
    '"' => ["Split horizontal", "split-window", "-v"],
    "v" => ["Split vertical", "split-window", "-h"],
    "b" => ["Split horizontal", "split-window", "-v"],
    "%" => ["Split vertical", "split-window", "-h"],
  }.each do |key, (note, command_name, direction)|
    bind key, note: do
      command command_name, *[direction, "-c", Tmux.pane_current_path].compact
    end
  end
  {h: ["left", "L"], j: ["down", "D"], k: ["up", "U"], l: ["right", "R"]}.each do |key, (name, direction)|
    bind key.to_s, "select-pane -#{direction}", note: "Select pane #{name}"
  end
  bind "m", "select-layout main-horizontal", note: "Main-horizontal"
  bind "M", "select-layout main-vertical", note: "Main-vertical"
  bind "C", 'command-prompt -p "Name of new window: " "new-window -n \'%%\'"',
    note: "New named window"
  bind "r", reload_config, note: "Reload config"

  bind "Space" do
    display_menu title: "Quick Actions" do
      item "Horizontal Split", key: "h", command: %q{split-window -v -c '#{pane_current_path}'}
      item "Vertical Split", key: "v", command: %q{split-window -h -c '#{pane_current_path}'}
      separator
      item "Swap Up", key: "u", command: "swap-pane -U"
      item "Swap Down", key: "d", command: "swap-pane -D"
      separator
      item "Kill Pane", key: "x", command: "kill-pane"
      item "Kill Window", key: "X", command: "kill-window"
    end
  end

  # The upstream value-less `set-window-option automatic-rename` toggles the
  # default from on to off when the config is loaded.
  window.automatic_rename = false
  server.default_terminal = "tmux-256color"
  server.terminal_overrides << ",xterm-256color:Tc"
  server.focus_events = true
  global.history_limit = 50_000

  tmux_from "3.2" do
    server.terminal_features << ",xterm*:RGB:extkeys"
    server.extended_keys = true
    bind "m", note: "Main-horizontal 66%" do
      command :set_window_option, "main-pane-height", "66%"
      command :select_layout, "main-horizontal"
    end
    bind "M", note: "Main-vertical 50%" do
      command :set_window_option, "main-pane-width", "50%"
      command :select_layout, "main-vertical"
    end
    bind "t", "display-popup -E -w 80% -h 80%", note: "Popup shell"
    bind "g", 'display-popup -E -w 80% -h 80% "git log --oneline --graph -30"',
      note: "Popup git log"
    window.copy_mode_match_style = "bg=colour136,fg=colour235"
    window.copy_mode_current_match_style = "bg=colour166,fg=colour235,bold"
    server.set_clipboard = true
    if?(shell("command -v clip.exe")) do
      server.copy_command = "clip.exe"
    end.else do
      if?(shell("command -v pbcopy")) do
        server.copy_command = "pbcopy"
      end.else do
        if?(shell("command -v xclip")) do
          server.copy_command = "xclip -selection clipboard >/dev/null"
        end
      end
    end
  end

  tmux_from("3.3") { window.pane_border_indicators = :arrows }
  tmux_from("3.5") { server.extended_keys_format = "csi-u" }
end
