# frozen_string_literal: true

require "tmux"

# Port of thoughtbot/dotfiles tmux.conf.
Tmux.configure do
  server.default_terminal = "screen-256color"
  window.mode_keys = :vi

  {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}"
  end
  bind "C-h", "select-window -t :-", repeat: true
  bind "C-l", "select-window -t :+", repeat: true

  global.prefix2 = "C-s"
  global.base_index = 1
  window.pane_base_index = 1
  global.renumber_windows = true

  global.status_style = "bg=#666666,fg=#aaaaaa"
  global.status_left = ""
  global.status_right = ""
  global.history_limit = 10_000

  bind "C-b", "send-prefix"
  bind "C-s", "send-prefix -2"
  unbind "C-z"

  if?(shell("[ -f ~/.tmux.conf.local ]")) do
    source "~/.tmux.conf.local"
  end
end
