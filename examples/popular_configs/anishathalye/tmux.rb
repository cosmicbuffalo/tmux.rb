# frozen_string_literal: true

require "tmux"

# Port of anishathalye/dotfiles tmux.conf.
Tmux.configure do
  server.default_terminal = "screen-256color"
  window.mode_keys = :vi

  {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}"
  end
  bind "C-h", "select-window -t :-", repeat: true
  bind "C-l", "select-window -t :+", repeat: true
  bind "v", "send -X begin-selection", table: "copy-mode-vi"
  bind "V", "send -X rectangle-toggle", table: "copy-mode-vi"
  bind "y", "send -X copy-selection-and-cancel", table: "copy-mode-vi"

  unbind "C-b"
  global.prefix = "C-a"
  %w[a C-a b C-b].each { |key| bind key, "send-prefix" }

  bind "c", 'new-window -c "#{pane_current_path}"'
  bind '"', 'split-window -c "#{pane_current_path}"'
  bind "%", 'split-window -h -c "#{pane_current_path}"'
  bind "<", 'select-pane -d \\; display-message "input disabled"'
  bind ">", 'select-pane -e \\; display-message "input enabled"'

  window.aggressive_resize = true
  global.mouse = true
  global.base_index = 1
  window.pane_base_index = 1
  {J: "D", K: "U", H: "L", L: "R"}.each do |key, direction|
    bind key, "resize-pane -#{direction} 5", repeat: true
  end
  bind "N", 'set-window-option automatic-rename on \\; display-message "automatic rename enabled"'
  global.renumber_windows = true
  window.monitor_activity = true
  server.escape_time = 0
  tmux_below("3.8") { global.display_panes_time = 2000 }
    .else { window.display_panes_time = 2000 }

  global.status_left_length = 20
  global.status_left = Tmux.format do
    switch_style(Tmux.pane_input_off => {fg: :colour160}, else: {fg: :colour136})
    wrap "[", "] " do
      text Tmux.session_name, ":", Tmux.window_index, "."
      if?(Tmux.client_prefix) { style fg: :colour166 }
      append Tmux.variable(:pane_index, shorthand: "#P")
    end
  end
  global.status_right.set(Tmux.format do
    style fg: :colour166
    command '[ "$(tmux show-option -g prefix)" != "prefix C-a" ] && ' \
      'echo "($(tmux show-option -g prefix | cut -c 8-)) "'
    style fg: :colour37
    command '[ -f $HOME/.name ] && cat $HOME/.name || hostname'
  end, expand: false)
  global.history_limit = 65_536

  bind "C-k", 'clear-history \\; display-message "history cleared"'
  bind "@", %q{command-prompt -p "create pane from:" "join-pane -s ':%%'"}
  bind "C-r", 'source-file ~/.tmux.conf \\; display-message "configuration reloaded"'
  bind "P", %q{if-shell "[ \"$(tmux show-options -g prefix)\" = \"prefix C-a\" ]" '    set -g prefix C-b; display-message "passthrough enabled"; refresh-client -S;     ' '    set -g prefix C-a; display-message "passthrough disabled"; refresh-client -S;     '}

  global.status_style = "bg=colour235,fg=colour136"
  window.window_status_style = "fg=colour244"
  window.window_status_current_style = "fg=colour166"
  window.window_status_activity_style = "fg=colour61"
  window.window_status_bell_style = "fg=colour61"
  window.pane_border_style = "fg=colour235"
  window.pane_active_border_style = "fg=colour240"
  global.message_style = "bg=colour235,fg=colour166"
  tmux_below("3.8") do
    global.display_panes_active_colour = :colour166
    global.display_panes_colour = :colour33
  end.else do
    window.display_panes_active_colour = :colour166
    window.display_panes_colour = :colour33
  end
  window.clock_mode_colour = :colour64

  if?(shell("[ -f ~/.tmux_local.conf ]")) do
    source "~/.tmux_local.conf"
  end
end
