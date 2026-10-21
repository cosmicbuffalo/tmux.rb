# frozen_string_literal: true

require "tmux"

# Port of nicknisi/dotfiles config/tmux/tmux.conf.
Tmux.configure do
  server.default_terminal = "tmux-256color"
  server.terminal_features << ",xterm-ghostty:RGB"
  server.terminal_features << ",xterm-ghostty:overline"
  global.update_environment << "COLORTERM"
  server.terminal_overrides << ',xterm*:sitm=\E[3m'
  server.extended_keys = :always
  tmux_from("3.5") { server.extended_keys_format = "csi-u" }
  server.terminal_features << ",xterm-ghostty:extkeys"
  server.terminal_features << ",xterm-ghostty:hyperlinks"
  server.terminal_overrides << ',*:Smulx=\E[4::%p1%dm'
  server.terminal_overrides << ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'
  tmux_from("3.3") { window.allow_passthrough = true }
  global.history_limit = 20_000
  global.renumber_windows = true
  global.status_interval = 3
  global.prefix = "C-a"
  bind "C-a", "send-prefix"
  bind "a", "send-prefix"
  server.set_clipboard = true
  global.mouse = true

  bind "MouseDown1Pane", <<~'TMUX'.lines(chomp: true).join(" "), no_prefix: true
    if-shell -F '#{mouse_hyperlink}'
      'run-shell -b "if command -v xdg-open >/dev/null 2>&1; then xdg-open #{q:mouse_hyperlink}; else open #{q:mouse_hyperlink}; fi"'
      'select-pane -t = ; send-keys -M'
  TMUX

  server.escape_time = 0
  global.base_index = 1
  window.pane_base_index = 1
  server.focus_events = true
  global.set_titles = true
  window.mode_keys = :vi
  global.status_keys = :vi
  window.automatic_rename = true
  window.automatic_rename_format = '#{window_name}'
  global.set_titles_string = "#T - #W"
  window.monitor_activity = false
  global.visual_activity = false
  window.aggressive_resize = true

  unbind "c"
  bind "c", 'new-window -c "#{pane_current_path}"'
  unbind "="
  bind "=", "select-layout tiled"
  bind "r", 'source-file ~/.config/tmux/tmux.conf \\; display "Config Reloaded!"'
  bind "|", 'split-window -h -c "#{pane_current_path}"'
  bind "-", 'split-window -v -c "#{pane_current_path}"'
  bind "y", "set-window-option synchronize-panes"
  {h: "L", j: "D", k: "U", l: "R"}.each do |key, direction|
    bind key, "select-pane -#{direction}"
  end
  bind "C-h", "select-window -t :-", repeat: true
  bind "C-l", "select-window -t :+", repeat: true
  {H: "L", J: "D", K: "U", L: "R"}.each do |key, direction|
    bind key, "resize-pane -#{direction} 10", repeat: true
  end

  bind "g", 'display-popup -w "80%" -h "80%" -d "#{pane_current_path}" -E "LG_CONFIG_FILE=\"\${XDG_CONFIG_HOME:-\$HOME/.config}/lazygit/config.yml,\$HOME/.local/state/theme/current/theme/lazygit.yml\" lazygit"'
  bind "y", 'display-popup -E -w 90% -h 70% "fleet"'
  bind "n", 'run-shell "fleet next"'
  bind "T", "set-option -g status", table: :prefix
  unbind "s"
  bind "s", 'display-popup -E -w 90% -h 70% "tm"'
  unbind "["
  bind "Escape", "copy-mode"
  unbind "p"
  bind "p", "paste-buffer"
  bind "v", "send -X begin-selection", table: "copy-mode-vi"

  run_shell "fleet reconcile >/dev/null 2>&1 &"
  run_shell "$HOME/.config/tmux/theme/theme.tmux"

  # Hooks and brace command blocks are not yet first-class config nodes.
  raw <<~'TMUX'
    set-hook -g @sketchybar-refresh {
      if-shell -F '#{&&:#{pane_active},#{window_active_clients}}' {
        if-shell -F '#{!=:#{@sketchybar_pending},1}' {
          set-option -g @sketchybar_pending 1
          run-shell -b -C -d 0.2 {
            set-option -g @sketchybar_pending 0
            run-shell -b 'sketchybar --trigger aerospace_focus_change 2>/dev/null || true'
          }
        }
      }
    }
    set-hook -g 'pane-title-changed[80]' 'set-hook -gR @sketchybar-refresh'
    set-hook -g 'after-select-pane[80]' 'set-hook -gR @sketchybar-refresh'
    set-hook -g 'after-select-window[80]' 'set-hook -gR @sketchybar-refresh'
    set-hook -g 'client-session-changed[80]' 'set-hook -gR @sketchybar-refresh'

    if-shell "[ -z \"$TMUX_MINIMAL\" ]" {
      set -g status on
    } {
      set -g status off
      set-hook -g after-new-window      'if "[ #{session_windows} -gt 1 ]" "set status on"'
      set-hook -g after-kill-pane       'if "[ #{session_windows} -lt 2 ]" "set status off"'
      set-hook -g pane-exited           'if "[ #{session_windows} -lt 2 ]" "set status off"'
      set-hook -g window-layout-changed 'if "[ #{session_windows} -lt 2 ]" "set status off"'
    }
  TMUX

  global[:@fleet_statusline_row] = :none
  global[:@fleet_chip_separator] = :none
  run_shell "fleet statusline --inject"
  bind "f", %q{run-shell "fleet sidebar --from '#{pane_id}'"}
  global.status = true

  raw <<~'TMUX'
    bind-key -n MouseDown1Status if-shell -F '#{m:sess-*,#{mouse_status_range}}' {
      run-shell 'tmux switch-client -t "=#{s/^sess-//:mouse_status_range}"'
    } {
      if-shell -F '#{||:#{==:#{mouse_status_range},window},#{==:#{mouse_status_range},}}' {
        select-window -t=
      } {
        run-shell 'fleet switch "#{mouse_status_range}" --from "#{pane_id}"'
      }
    }
    bind-key -n MouseDown3Status if-shell -F '#{&&:#{!=:#{mouse_status_range},},#{!=:#{mouse_status_range},window}}' {
      run-shell 'fleet ack "#{mouse_status_range}" --from "#{pane_id}"'
    }
    bind-key -n MouseDown1StatusLeft display-popup -E -w 90% -h 70% "tm"
  TMUX
end
