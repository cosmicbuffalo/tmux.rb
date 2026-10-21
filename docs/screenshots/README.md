# Screenshots

The images in `docs/images` are real screenshots of real tmux sessions, each
rendering the README example just above it. `script/screenshots` makes them:

```bash
bundle exec rake screenshots                         # every scene
bundle exec rake screenshots SCENES="chips zones"    # just some
```

A README example opts in with a marker right before its code block:

    <!-- example: chips -->
    ```ruby
    Tmux.format do
      ...

and a scene in [`scenes.rb`](scenes.rb) says how to show it: which option a
format fills, which windows to open, setup commands (splitting or zooming a
pane), and keys to press (such as the prefix). For each scene the script:

1. evaluates the example on top of a small base configuration that sets the
   status bar to the terminal's own colors and leaves it empty, so the image
   shows only what the example draws;
2. starts a throwaway tmux server (its own socket in a temporary directory)
   with fixed windows and a fake `$HOME` and hostname, so images never show
   real paths, machine names, or the time;
3. attaches a real terminal with [VHS](https://github.com/charmbracelet/vhs)
   (xterm.js in headless Chromium), presses the scene's keys, and saves the
   screen to `docs/images/NAME.png`; and
4. crops the image to the status line, unless the scene sets `full: true`.

The terminal uses VHS's built-in **Catppuccin Mocha** theme and JetBrains
Mono Nerd Font at 18px. The theme decides how named colors (`:blue`,
`colour1`, ...) and the default colors look; `colour16`-`colour255` and hex
colors are the same in any terminal.

Rendering is deterministic: re-running it only changes an image when its
example, scene, or the library changed. `test/screenshot_scenes_test.rb`
checks that every scene has a README example and image and that every
example loads into tmux, without rendering anything.

## Requirements

- tmux
- [VHS](https://github.com/charmbracelet/vhs#installation), with its
  dependencies `ttyd` and `ffmpeg` (VHS downloads Chromium if needed)

Powerline glyphs need a Nerd Font. The script downloads a pinned release of
JetBrains Mono Nerd Font (SIL Open Font License), verifies its checksum, and
keeps it in `tmp/screenshots`, exposed to Chromium through a private
fontconfig file, so nothing is installed system-wide.
