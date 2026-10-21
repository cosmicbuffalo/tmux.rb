# Screenshot scenes, rendered by script/screenshots into docs/images/NAME.png.
# Each renders the README example after an `<!-- example: NAME -->` marker.
#
# name:     image name
# example:  the README example's marker name
# option:   for an example that builds a format, the option(s) it fills
# windows:  windows to open (default: one named zsh); each pane shows
#           `content` and runs as `command`
# select:   the window to show (default: the first)
# setup:    tmux commands run before the terminal attaches; "%{idle PROGRAM}"
#           is a pane idling as PROGRAM (see FAKE_PROGRAMS in the script), and
#           %{project} is the panes' working directory
# keys:     VHS commands run after it attaches, e.g. "Ctrl+B" for the prefix
# full:     show the whole terminal instead of just the status line
# height:   the terminal height in pixels, for full scenes

WINDOWS = [
  {name: "editor", command: "nvim"},
  {name: "tests", command: "ruby"},
  {name: "logs", command: "tail"}
].freeze

ZOOMED = [["split-window", "-h", "-c", "%{project}", "%{idle zsh}"], %w[last-pane], %w[resize-pane -Z]].freeze

[
  {name: "intro", example: "intro", windows: [{name: "zsh", command: "nvim"}], setup: ZOOMED},
  {name: "window-tab", example: "window-tab", windows: WINDOWS, select: "tests",
   option: %w[window-status-format window-status-current-format],
   # The logs window is mid-flash.
   setup: [%w[set-option -w -t demo:logs @attn_flash 1], %w[set-option -w -t demo:logs @attn_phase 1]]},
  {name: "styles", example: "styles", option: "status-left"},
  {name: "conditionals", example: "conditionals", option: "status-left", setup: ZOOMED},
  {name: "switch", example: "switch", option: "status-left", setup: [%w[select-pane -d]]},
  {name: "switch-prefix", example: "switch", option: "status-left", keys: ["Ctrl+B"]},
  {name: "switch-copy-mode", example: "switch", option: "status-left", keys: ["Ctrl+B", 'Type "["']},
  {name: "wrap", example: "wrap", option: "status-left"},
  {name: "status-right", example: "status-right", option: "status-right"},
  {name: "status-left", example: "status-left", option: "status-left"},
  {name: "chips", example: "chips", option: "status-left"},
  {name: "zones", example: "zones", full: true, height: 420,
   windows: [{name: "work", command: "nvim"}],
   setup: [["split-window", "-h", "-c", "%{project}", "%{idle ruby}"]]}
]
