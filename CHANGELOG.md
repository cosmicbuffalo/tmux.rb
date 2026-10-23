# Changelog

## Unreleased

### Development

- Merging a version bump to main tags it and creates a GitHub release once
  CI passes on that commit, with the version's CHANGELOG section as the
  notes (`script/release-notes VERSION` prints it). A test fails if the
  current version has no CHANGELOG section.

## 0.2.0 (2026-10-23)

### Library

- `bind(key)` with no command or block returns a chain of named commands:
  `bind("-").split(:vertical).cwd(:current)`, `bind("c").new_window`.
- Named binding commands `split`, `new_window`, `cwd`, `resize_pane`, `zoom`,
  `kill_pane`, `kill_window`, and `source`, and a direction for
  `select_pane`. `split` accepts `:vertical`/`:horizontal` or the shorthand
  `:v`/`:h`. They work in chains and in binding blocks.
- `comment` writes `#` lines into the generated file, and `hook` sets a
  tmux hook (command string or block, optional `index:` slot, `:global`,
  `:window`, or `:pane` scope).

### Fixes

- `shell(...)` conditions reach the shell exactly as written. tmux no longer
  expands `$` variables when the file loads or rejects shell syntax such as
  `${VAR:-default}`.

### Documentation

- The README opens with a hand-written tmux.conf beside its tmux.rb version,
  and Examples move up ahead of Why. Tests check that both versions load
  identically and that the key binding examples match their tmux comments.

## 0.1.0 (2026-10-21)

First public release, as the `tmux` gem (`require "tmux"`), with the
`tmux.rb` command (also installed as `tmux_rb`).

### Library

- `Tmux.configure` and `Tmux.format` DSLs that compile to deterministic
  tmux configuration and format strings. `Tmux.load_file` evaluates a
  configuration file in its own anonymous module.
- `text` with interpolated expressions kept dynamic and everything else
  literal (escaping `#`, and `%` once per conditional nesting level), plus
  `strftime`, `append`, and `#(...)` `command` content, each with its own
  escaping, verified by rendering in real tmux servers.
- Expressions: `!`, string `==`/`!=`, numeric `>`, `<`, `>=`,
  `<=`, `matches`, and `substitute`. Booleans and other non-expression values
  raise instead of compiling silently.
- Automatic `&&` / `||` capture in `if?` / `.elsif?` conditions and inline
  `switch` / `switch_style` keys in files compiled by the CLI or `Tmux.load_file`.
  The private source compiler uses Prism; no public `condition` helper or
  expression `&` / `|` operators are needed.
- Runtime selection with `Tmux.switch` and `switch_style`, Powerline helpers
  (`left_flag`, `right_segment`, `chip`, ...), and `Tmux.pane_border` zones.
- Complete target-specific option discovery from the selected tmux executable
  (`--tmux PATH` or `tmux:` in Ruby). Scoped setters validate built-in names,
  scopes, and array indices; inactive version branches are excluded. Custom
  options use scoped brackets such as `global[:@plugin]`. Generic option-setting
  helpers are removed. Loading refuses a mismatched server version.
- Option names grouped by tmux's own scopes (`global`, `window`,
  `server`), key-binding command blocks and menus, configuration
  `if?`/`.elsif?`/`.else` chains with tmux expressions or deferred `shell(...)`
  exit-status checks (including background checks), compiled to `{ }` command
  blocks, and `tmux_from`/`tmux_below` compiled to `%if` checks
  on the running server's version. Generated configurations need tmux 3.2+;
  CI tests every release from 3.2 to 3.8 and tmux's development branch.
- Nested blocks keep helper methods and instance variables in scope; a block
  may also take its builder as a parameter.

### CLI

- `tmux.rb build`, `check`, `diff`, and `load` (with `-S`/`-L` to choose the
  server), plus `--version` and per-command `--help`.
- `build --output` writes atomically, follows a symlinked destination, and
  keeps an existing file's permissions.
- Errors raised by a configuration name the file and line that raised them.

### Examples

- `examples/author_config.rb`, a complete real-world configuration with
  pinned output and tmux-rendered window-tab tests.
- Ten ports of popular public tmux configurations, checked for equivalence
  against their upstream originals in isolated tmux servers on every tested
  tmux version.

### Development

- `rake test:tmux` and a CI job build tmux 3.2a through 3.8 and the
  development branch from source and run the suite against each.
