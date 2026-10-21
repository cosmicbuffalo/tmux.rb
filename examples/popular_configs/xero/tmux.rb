# frozen_string_literal: true

require "tmux"

# Port of xero/dotfiles tmux/.config/tmux/tmux.conf.
Tmux.configure do
  shell = ENV.fetch("SHELL", "/bin/sh")
  global.default_command = shell
  global.default_shell = shell
  global.base_index = 1
  global.renumber_windows = true
  window.pane_base_index = 1
  server.escape_time = 0
  global.history_limit = 10_000
  server.terminal_overrides = "xterm*:smcup@:rmcup@"
  server.terminal_features << ",xterm-256color:RGB"
  window.mode_keys = :vi
  global.status_keys = :vi
  global.mouse = true
  server.focus_events = true

  window.pane.border.style = "fg=color0"
  window.pane.border.lines = :heavy
  window.pane.active_border.style = "fg=color0"
  window.active_style = "bg=terminal"
  window.style = "bg=#1c1427"
  global.status_justify = :left
  global.status_style = "bg=terminal,fg=color10"
  global.status_interval = 2
  global.message.style = "bg=color4,fg=color10"
  global.message.command_style = "bg=color12,fg=color2"
  window.mode_style = "bg=color8,fg=color4"
  window.pane.border.style = "bg=color0,fg=color5"
  window.pane.active_border.style = "bg=color0,fg=color5"
  window.aggressive_resize = true
  global.status.position = :bottom
  window.status.format = " #[bg=color4,fg=color0,noreverse]▓░ #W "
  window.status.current.format = " #[bg=color10,fg=color0,noreverse]▓░ #W "
  global.visual_activity = true
  global.visual_bell = false
  global.visual_silence = false
  window.monitor_activity = false
  global.bell_action = :none
  window.clock_mode_colour = :color4

  unbind "C-b"
  global.prefix = "`"
  bind "`", "send-prefix"
  unbind "["
  bind "Escape", "copy-mode"
  unbind "p"
  bind "p", "paste-buffer"
  bind "v", "send -X begin-selection", table: "copy-mode-vi"
  bind "y", 'send -X copy-pipe-and-cancel "yank" \\; send-keys enter', table: "copy-mode-vi"
  bind "Y", 'send -X copy-pipe-and-cancel "tmux loadb -" \\; send-keys enter', table: "copy-mode-vi"
  unbind "%"
  bind "h", "split-window -v"
  unbind '"'
  bind "v", "split-window -h"
  unbind "z"
  raw <<~'TMUX'
    is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
        | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
    bind z if-shell "$is_vim" "send-keys ,z" "resize-pane -Z"
  TMUX
  bind "Z", "resize-pane -Z"
  bind ":", "command-prompt"
  bind "r", 'source-file ~/.config/tmux/tmux.conf \\; display-message "█▓░ reloaded"'
  bind "x", "kill-pane"
  bind "t", "set status"
  bind "a", 'set-window-option synchronize-panes \\; display-message "█▓░ synchronize"'

  global[:@plugin] = "tmux-plugins/tpm"
  raw "set-environment -g TMUX_PLUGIN_MANAGER_PATH '~/.config/tmux/plugins/'"
  global[:@plugin] = "fcsonline/tmux-thumbs"
  {
    "thumbs-key" => "f",
    "thumbs-contrast" => 1,
    "thumbs-bg-color" => "#b968fc",
    "thumbs-fg-color" => "#201430",
    "thumbs-hint-bg-color" => "#87ff5f",
    "thumbs-hint-fg-color" => "#201430",
    "thumbs-select-bg-color" => "#9CDA7C",
    "thumbs-select-fg-color" => "#201430",
    "thumbs-command" => 'printf "{}" | yank'
  }.each { |name, value| global["@#{name}"] = value }
  unbind "f"

  global[:@plugin] = "MunifTanjim/tmux-mode-indicator"
  {
    mode_indicator_empty_prompt: " ◇ ",
    mode_indicator_empty_mode_style: "bg=term,fg=color2",
    mode_indicator_prefix_prompt: " ◈ ",
    mode_indicator_prefix_mode_style: "bg=color2,fg=color0",
    mode_indicator_copy_prompt: "  ",
    mode_indicator_copy_mode_style: "bg=color10,fg=color0",
    mode_indicator_sync_prompt: "   ",
    mode_indicator_sync_mode_style: "bg=color6,fg=color0"
  }.each { |name, value| global["@#{name}"] = value }

  global[:@plugin] = "aserowy/tmux.nvim"
  {
    "tmux-nvim-navigation" => "true",
    "tmux-nvim-navigation-cycle" => "true",
    "tmux-nvim-navigation-keybinding-left" => "C-h",
    "tmux-nvim-navigation-keybinding-down" => "C-j",
    "tmux-nvim-navigation-keybinding-up" => "C-k",
    "tmux-nvim-navigation-keybinding-right" => "C-l",
    "tmux-nvim-resize" => "true",
    "tmux-nvim-resize-step-x" => 1,
    "tmux-nvim-resize-step-y" => 1,
    "tmux-nvim-resize-keybinding-left" => "C-Left",
    "tmux-nvim-resize-keybinding-down" => "C-Down",
    "tmux-nvim-resize-keybinding-up" => "C-Up",
    "tmux-nvim-resize-keybinding-right" => "C-Right"
  }.each { |name, value| global["@#{name}"] = value }

  global.status_right_length = 100
  global.status_right = "#(~/.local/bin/tmux-status)"
  global.status_left = '#{tmux_mode_indicator}'
  server.set_clipboard = true
  server.terminal_overrides << 'vte*:XT:Ms=\\E]52;c;%p2%s\\7,xterm*:XT:Ms=\\E]52;c;%p2%s\\7'
  unbind "p"
  bind "p", "paste-buffer -p"
  bind "Space", %q{display-popup -b "heavy" -S 'bg=color0,fg=color4' -w 70% -h 70% -E "CM_OUTPUT_CLIP=1 clipmenu | yank"}
  bind "e", %q{display-popup -b "heavy" -S 'bg=color0,fg=color4' -w 70% -h 70% -E "emoji"}
  run_shell "~/.config/tmux/plugins/tpm/tpm"
end
