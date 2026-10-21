# frozen_string_literal: true

require "tmux"

# Port of dikiaap/dotfiles .tmux/tmux.conf.
Tmux.configure do
  def reload_config
    load_config "~/.config/tmux/tmux.rb", message: "tmux reloaded"
  end

  server.default_terminal = "screen-256color"
  window.mode_keys = :vi
  global.status_keys = :vi
  global.mouse = true
  server.escape_time = 0
  server.focus_events = true
  global.history_limit = 10_000
  server.history_file = "~/.tmux/tmuxhistory"
  window.monitor_activity = true
  global.visual_activity = false
  global.base_index = 1
  window.pane_base_index = 1
  window.automatic_rename = true
  global.renumber_windows = true
  global.bell_action = :none
  server.terminal_features << ",xterm-256color:RGB"

  unbind "C-b"
  global.prefix = "C-a"
  bind "C-a", "send-prefix"
  bind "r", reload_config

  {"M-h" => "L", "M-j" => "D", "M-k" => "U", "M-l" => "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}", no_prefix: true
  end
  unbind "n"
  bind "M-p", "previous-window", no_prefix: true
  bind "M-n", "next-window", no_prefix: true
  (1..9).each { |index| bind "M-#{index}", "select-window -t:#{index}", no_prefix: true }
  bind "M-0", "select-window -t:10", no_prefix: true

  unbind '"'
  unbind "%"
  bind "-", 'split-window -v -c "#{pane_current_path}"'
  bind "\\", 'split-window -h -c "#{pane_current_path}"'
  bind "_", 'split-window -fv -c "#{pane_current_path}"'
  bind "|", 'split-window -fh -c "#{pane_current_path}"'
  {"M-H" => ["L", 2], "M-J" => ["D", 1], "M-K" => ["U", 1], "M-L" => ["R", 2]}.each do |key, (direction, amount)|
    bind key, "resize-pane -#{direction} #{amount}", no_prefix: true
  end
  bind "M-z", "resize-pane -Z", no_prefix: true
  unbind "{"
  unbind "}"
  bind "H", "swap-pane -U", repeat: true
  bind "L", "swap-pane -D", repeat: true
  bind "x", "kill-pane"
  bind "<", "swap-window -t -1", repeat: true
  bind ">", "swap-window -t +1", repeat: true
  unbind "&"
  bind "X", "kill-window"
  bind "K", "kill-window -a"
  bind "M-v", "copy-mode", no_prefix: true

  {v: "begin-selection", V: "select-line", "C-v": "rectangle-toggle"}.each do |key, action|
    bind key, "send-keys -X #{action}", table: "copy-mode-vi"
  end
  %w[y Enter].each do |key|
    bind key, 'send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"', table: "copy-mode-vi"
  end
  bind "Escape", "send-keys -X cancel", table: "copy-mode-vi"
  bind "p", 'paste-buffer -s ""'
  bind "P", %q{choose-buffer "paste-buffer -b '%%' -s ''"}
  unbind "MouseDragEnd1Pane", table: "copy-mode-vi"
  {
    "WheelUpPane" => :scroll_up,
    "WheelDownPane" => :scroll_down,
  }.each do |key, action|
    bind key, table: "copy-mode-vi" do
      select_pane
      copy_mode :clear_selection, target: "{mouse}"
      copy_mode action, target: "{mouse}", count: 5
    end
  end
  bind "/", 'copy-mode \\; send-keys "/"'
  bind "?", 'copy-mode \\; send-keys "?"'
  bind "H", 'new-window "htop" \\; set-option -w monitor-activity off'

  window.mode_style = {bg: :brightblack, fg: :default}
  global.status = true
  global.status.position = :top
  global.status.interval = 5
  global.status.style = {bg: :default, fg: :white}
  global.status.left.length = 40
  global.status_left = Tmux.format do
    style(fg: :brightwhite, bg: :brightblack, p: 1) { append Tmux.session_name }
    style fg: :default, bg: :default
    text " "
  end
  window.window_status_format = Tmux.format do
    style(fg: :white, bg: :brightblack, p: 1) { append Tmux.window_index }
    style(fg: :white, bg: "#363636", p: 1) { append Tmux.window_name }
  end
  window.window_status_current_format = Tmux.format do
    style(fg: :brightwhite, bg: :green, p: 1) { append Tmux.window_index }
    style(fg: :brightwhite, bg: :blue, p: 1) { append Tmux.window_name }
  end
  window.status.separator = " "
  global.status.justify = :left
  global.status.right.length = 40
  global.status_right = Tmux.format do
    text " "
    style fg: :brightwhite, bg: "#363636"
    strftime " %a, %d %b %H:%M "
    style fg: :brightwhite, bg: :brightblack
    text " "
    command "whoami"
    text "@"
    append Tmux.host_short
    text " "
  end
  window.pane.border.style = {bg: :default, fg: :brightblack}
  window.pane.active_border.style = {bg: :default, fg: :white}
  tmux_below("3.8") do
    global.display_panes.colour = :brightblack
    global.display_panes.active_colour = :brightwhite
  end.else do
    window.display_panes.colour = :brightblack
    window.display_panes.active_colour = :brightwhite
  end
  window.clock.colour = :white
  window.clock.hour_format = 24
  global.message.style = {bg: :default, fg: :default}

  global["@emulate-scroll-for-no-mouse-alternate-buffer"] = "on"
  run_shell "~/.local/src/tmux-better-mouse-mode/scroll_copy_mode.tmux"
  run_shell "~/.local/src/tmux-copycat/copycat.tmux"
end
