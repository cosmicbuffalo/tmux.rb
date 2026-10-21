# frozen_string_literal: true

require "tmux"

# Port of alrra/dotfiles src/tmux/tmux.conf.
Tmux.configure do
  global.base_index = 1
  window.pane_base_index = 1
  server.escape_time = 1

  global.prefix = "C-a"
  unbind "C-b"
  bind "C-a", "send-prefix"

  window.mode_keys = :vi
  if?(shell('test "$(uname -s)" = Darwin')) do
    global.default_command = 'exec reattach-to-user-namespace -l $SHELL'
  end

  unbind "["
  bind "Escape", "copy-mode"
  unbind "p"
  bind "p", "paste-buffer"
  bind "v", "send-keys -X begin-selection", table: "copy-mode-vi"
  bind "y", "send-keys -X copy-selection", table: "copy-mode-vi"

  bind "-", "split-window -v"
  bind "|", "split-window -h"
  {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}"
    bind key.upcase, "resize-pane -#{direction} 5", repeat: true
  end
  bind "r", 'source-file ~/.tmux.conf \\; display "tmux configs reloaded"'

  window.monitor_activity = true
  global.visual_activity = true
  global.status_interval = 60
  global.status_justify = :left
  global.status_left_length = 50
  global.status_left = " #S / "
  global.status_right = " %R "
  global.status_bg = :green
  global.status_fg = :black
  window.window_status_style = "fg=black,bg=green,dim"
  window.window_status_current_style = "fg=black,bg=yellow,dim"

  server.default_terminal = "screen-256color"
  global.message_style = "fg=black,bg=green,dim"
  window.pane_active_border_style = "bg=default,fg=green"
  window.pane_border_style = "bg=default,fg=colour244"
end
