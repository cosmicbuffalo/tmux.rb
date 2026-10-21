# frozen_string_literal: true

require_relative "profile"

# A complete Ruby-native equivalent of Oh My Tmux's default profile. This is
# the customization layer users edit; profile.rb replaces the legacy polyglot
# tmux/shell framework underneath it.
OhMyTmux.configure(source_path: __FILE__) do
  self.preserve_stock_bindings = false
  self.new_session_prompt = false
  self.new_session_retain_current_path = false
  self.new_window_retain_current_path = false
  self.new_window_reconnect_ssh = false
  self.new_pane_retain_current_path = true
  self.new_pane_reconnect_ssh = false
  self.copy_to_os_clipboard = false

  {
    1 => "#080808", 2 => "#303030", 3 => "#8a8a8a",
    4 => "#00afff", 5 => "#ffff00", 6 => "#080808",
    7 => "#e4e4e4", 8 => "#080808", 9 => "#ffff00",
    10 => "#ff00af", 11 => "#5fff00", 12 => "#8a8a8a",
    13 => "#e4e4e4", 14 => "#080808", 15 => "#080808",
    16 => "#d70000", 17 => "#e4e4e4"
  }.each { |number, value| color number, value }
end
