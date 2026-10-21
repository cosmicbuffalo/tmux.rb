# frozen_string_literal: true

require "tmux"

# Port of skwp/dotfiles tmux/tmux.conf (YADR).
Tmux.configure do
  global.bell_action = :any
  server.default_terminal = "screen-256color"
  bind "C-d", "detach-client"

  bind "v", 'split-window -h -p 50 -c "#{pane_current_path}"'
  bind "C-v", 'split-window -h -p 50 -c "#{pane_current_path}"'
  bind "s", 'split-window -p 50 -c "#{pane_current_path}"'
  bind "C-s", 'split-window -p 50 -c "#{pane_current_path}"'
  {H: "L", J: "D", K: "U", L: "R"}.each do |key, direction|
    bind key, "resize-pane -#{direction} 5", repeat: true
  end

  # tmux config-local variables are intentionally left as a small raw island.
  raw <<~'TMUX'
    is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
        | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
    bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h'  'select-pane -L'
    bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j'  'select-pane -D'
    bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k'  'select-pane -U'
    bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l'  'select-pane -R'

    tmux_version='$(tmux -V | sed -En "s/^tmux ([0-9]+(.[0-9]+)?).*/\1/p")'
    if-shell -b '[ "$(echo "$tmux_version < 3.0" | bc)" = 1 ]' \
        "bind-key -n 'C-\\' if-shell \"$is_vim\" 'send-keys C-\\'  'select-pane -l'"
    if-shell -b '[ "$(echo "$tmux_version >= 3.0" | bc)" = 1 ]' \
        "bind-key -n 'C-\\' if-shell \"$is_vim\" 'send-keys C-\\\\'  'select-pane -l'"
  TMUX

  %w[C-h C-j C-k C-l].zip(%w[L D U R]).each do |key, direction|
    bind key, "select-pane -#{direction}", table: "copy-mode-vi"
  end
  bind 'C-\\', "select-pane -l", table: "copy-mode-vi"

  global.status_keys = :vi
  window.mode_keys = :vi
  bind "e", "set-window-option synchronize-panes on"
  bind "E", "set-window-option synchronize-panes off"
  global.base_index = 1
  window.pane_base_index = 1
  global.mouse = true

  global.status_left_length = 52
  global.status_right_length = 451
  global.status_style = "fg=white,bg=colour234"
  window.pane_border_style = "fg=colour245"
  window.pane_active_border_style = "fg=colour39"
  global.message_style = "fg=colour16,bg=colour221,bold"
  global.status_left = "#[fg=colour235,bg=colour252,bold] ❐ #S #[fg=colour252,bg=colour238,nobold]⮀#[fg=colour245,bg=colour238,bold] #(whoami) #[fg=colour238,bg=colour234,nobold]⮀"
  window.window_status_format.set('#[fg=colour235,bg=colour252,bold] #I #(pwd="#{pane_current_path}"; echo ${pwd####*/}) #W ', expand: false)
  window.window_status_current_format.set('#[fg=colour234,bg=colour39]⮀#[fg=black,bg=colour39,noreverse,bold] #{?window_zoomed_flag,#[fg=colour228],} #I #(pwd="#{pane_current_path}"; echo ${pwd####*/}) #W #[fg=colour39,bg=colour234,nobold]⮀', expand: false)
  global.status_interval = 2

  global.default_command = 'which reattach-to-user-namespace > /dev/null && reattach-to-user-namespace -l $SHELL || $SHELL'
  unbind "C-b"
  global.prefix = "C-a"
  bind "a", "send-prefix"
  server.escape_time = 0
  unbind "l"
  bind "C-a", "last-window"
  global.history_limit = 10_000
  bind "c", 'new-window -c "#{pane_current_path}"'
  global.assume_paste_time = 0
  unbind "r"
  bind "r", 'source-file ~/.tmux.conf \\; display "Reloaded!"'
  if?(shell("[ -f ~/.tmux.conf.user ]")) do
    source "~/.tmux.conf.user"
  end
end
