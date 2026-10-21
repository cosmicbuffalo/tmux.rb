# frozen_string_literal: true

require "tmux"

# Port of square/maximum-awesome tmux.conf (Apache License 2.0, see LICENSE).
# Modified by Nick deLannoy, 2026: translated into a tmux.rb configuration.
Tmux.configure do
  global.prefix = "C-a"
  unbind "C-a"
  bind "C-a", "send-prefix"
  global.base_index = 1
  bind "R", 'source-file ~/.tmux.conf \\; display-message "tmux.conf reloaded."'
  window.mode_keys = :vi
  global.mouse = true
  server.default_terminal = "screen-256color"

  bind ":", "command-prompt"
  bind "r", "refresh-client"
  bind "L", "clear-history"
  bind "Space", "next-window"
  bind "BSpace", "previous-window"
  bind "Enter", "next-layout"
  bind "v", 'split-window -h -c "#{pane_current_path}"'
  bind "s", 'split-window -v -c "#{pane_current_path}"'
  {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}"
  end
  bind "C-o", "rotate-window"
  bind "+", "select-layout main-horizontal"
  bind "=", "select-layout main-vertical"
  window.other_pane_height = 25
  window.other_pane_width = 80
  bind "a", "last-pane"
  bind "q", "display-panes"
  bind "c", "new-window"
  bind "t", "next-window"
  bind "T", "previous-window"
  bind "[", "copy-mode"
  bind "]", "paste-buffer"

  run_shell 'tmux setenv -g TMUX_VERSION $(tmux -V | cut -c 6-)'
  bind "v", "send-keys -X begin-selection", table: "copy-mode-vi"
  bind "y", 'send-keys -X copy-pipe-and-cancel "reattach-to-user-namespace pbcopy"', table: "copy-mode-vi"
  unbind "Enter", table: "copy-mode-vi"
  bind "Enter", 'send-keys -X copy-pipe-and-cancel "reattach-to-user-namespace pbcopy"', table: "copy-mode-vi"
  tmux_below("3.8") { global.display_panes_time = 1500 }
    .else { window.display_panes_time = 1500 }

  global.status_interval = 1
  global.status_left = ""
  global.status_right = "%l:%M%p"
  window.window_status_current_style = "fg=magenta"
  global.status_style = "fg=default"
  global.status_style = "bg=black"
  window.pane_active_border_style = "fg=black"
  window.pane_border_style = "fg=black"

  if?(shell('[ "$COLORFGBG" = "11;15" ]')) do
    global.status_style = "bg=white"
  end
  if?(shell('[ "$COLORFGBG" = "11;15" ]')) { window.pane_active_border_style = "fg=white" }
  if?(shell('[ "$COLORFGBG" = "11;15" ]')) { window.pane_border_style = "fg=white" }

  window.monitor_activity = true
  global.visual_activity = true
  global.default_command = "/bin/bash -c 'which reattach-to-user-namespace >/dev/null && exec reattach-to-user-namespace $SHELL -l || exec $SHELL -l'"
  global.repeat_time = 0
  bind "WheelUpPane",
    'if-shell -F -t = "#{alternate_on}" "send-keys -M" "select-pane -t =; copy-mode -e; send-keys -M"',
    table: :root
  bind "WheelDownPane",
    'if-shell -F -t = "#{alternate_on}" "send-keys -M" "select-pane -t =; send-keys -M"',
    table: :root
  global.assume_paste_time = 0
  source "~/.tmux.conf.local"
end
