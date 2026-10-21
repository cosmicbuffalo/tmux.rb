# A standalone window-status format, rendered with:
#   tmux.rb build examples/window_status.rb
#   CURRENT=1 tmux.rb build examples/window_status.rb

require "tmux"

current = ENV.fetch("CURRENT", "0") == "1"

colors = if current
  {index_fg: "#000000", index_bg: "#ff8800", name_fg: "#ffffff", name_bg: "#4e4e4e"}
else
  {index_fg: "#2d2d30", index_bg: "#5eaceb", name_fg: "#5eaceb", name_bg: "#2d2d30"}
end

attn_state = Tmux.user_option(:@ai_attn_window_state)
attn_flash = Tmux.user_option(:@ai_attn_window_flash)
flash_phase = Tmux.user_option(:@ai_attn_flash_phase)
zoomed = Tmux.variable(:window_zoomed_flag)
synchronized = Tmux.variable(:pane_synchronized)

Tmux.format do
  style fg: colors[:index_fg], bg: colors[:index_bg]
  text " "
  append Tmux.variable(:window_index)
  text " "

  style fg: colors[:name_fg], bg: colors[:name_bg]
  if?(!attn_state) { text " " }
  expand_option :@ai_attn_window_segment

  # Preserve the flash background through the name only during its on phase.
  if?(!(attn_flash && flash_phase)) { style fg: colors[:name_fg], bg: colors[:name_bg] }

  if?(zoomed) do
    if?(!(attn_flash && flash_phase)) { style fg: "colour44" }
    text "("
  end

  append Tmux.variable(:window_name)

  if?(zoomed) do
    if?(!(attn_flash && flash_phase)) { style fg: "colour44" }
    text ")"
  end

  text " "

  if?(synchronized) do
    style fg: "brightred"
    text "(sync) "
  end

  reset_style
end
