# Popular tmux config ports

This corpus favors recognizable, varied configurations over a strict ranking.
Each directory keeps the pinned upstream config and its tmux.rb port together:

- `original.tmux.conf` is the upstream tmux configuration.
- `tmux.rb` is the equivalent tmux.rb configuration.
- `LICENSE` is the upstream license covering the copied example. Each
  `tmux.rb` is a modified, derivative work of its upstream config, translated
  into tmux.rb and distributed under that same license. tony/tmux-config ships
  no LICENSE file; its README states "LICENSE: MIT", so `tony/LICENSE` is the
  standard MIT text with Tony Narlock's copyright.
- Additional `original.*` files preserve companion files sourced by the config.

## Sources

| Example | Upstream revision | What it exercises |
| --- | --- | --- |
| `tony` | [tony/tmux-config@40d4b0c](https://github.com/tony/tmux-config/tree/40d4b0ce6fd750b6de2520f71857bfc4feb27315) | Menus, annotated bindings, format ASTs, nested clipboard detection, and version gates |
| `oh_my_tmux` | [gpakosz/.tmux@58a3dcc](https://github.com/gpakosz/.tmux/tree/58a3dcc0d718ec0fa1c0d5a2fddd640a1ad7a5b7) | Ruby-native framework/profile port, generated theme, rewritten bindings, and runtime indicators |
| `thoughtbot` | [thoughtbot/dotfiles@939a270](https://github.com/thoughtbot/dotfiles/tree/939a27005b2dd4ac1556e104fc91122f3aea0a6c) | Vim-style navigation and conditional shell commands |
| `skwp` | [skwp/dotfiles@630d39f](https://github.com/skwp/dotfiles/tree/630d39fb1dfbddd1cf1eca94ef6fb58c336971f5) | Legacy compatibility and platform conditionals |
| `maximum_awesome` | [square/maximum-awesome@5b214ed](https://github.com/square/maximum-awesome/tree/5b214ed692a76a673d8bc1adabe4654a23f85c0e) | Project config with a sourced local override |
| `nicknisi` | [nicknisi/dotfiles@f4fdb8e](https://github.com/nicknisi/dotfiles/tree/f4fdb8e26433e10d4b1e47733603c60b380f3151) | Hooks, popups, mouse tables, and a sourced theme |
| `xero` | [xero/dotfiles@5204a2b](https://github.com/xero/dotfiles/tree/5204a2b74f9af6b979b88f71a696eca872396a33) | TPM plugins, user options, formats, and extensive bindings |
| `alrra` | [alrra/dotfiles@a810a23](https://github.com/alrra/dotfiles/tree/a810a2393aa8987e36e251b83fb79590f1382adc) | Version gates and OS-dependent commands |
| `dikiaap` | [dikiaap/dotfiles@ef6e4bd](https://github.com/dikiaap/dotfiles/tree/ef6e4bdee7ddb17631911b1530398bbfa7423a52) | Rich status styling and plugin declarations |
| `anishathalye` | [anishathalye/dotfiles@f7e7ecb](https://github.com/anishathalye/dotfiles/tree/f7e7ecb638208c51941955adf5f2cc80a00e415b) | Nested tmux version checks and terminal features |

All ten examples are direct ports. The Oh My Tmux directory additionally has
`profile.rb`, which replaces the upstream polyglot configuration engine, and
`runtime.rb`, which replaces its username, hostname, battery, uptime, pane
maximization, and path-picker shell helpers. Its generated config never sources
or extracts the legacy `.tmux.conf`.

## Equivalence tests

`test/popular_configs_equivalence_test.rb` loads each original and generated
configuration into separate isolated tmux servers, then compares global,
window, and server options; all key tables; global hooks; and global
environment. Top-level external integration commands are normally replaced
with `/bin/true`, so the tests do not install plugins or execute
workstation-specific scripts. The Oh My Tmux case instead runs the complete
upstream engine in a scrubbed environment with no plugins, then compares it to
the standalone Ruby implementation. Only transient metrics, private worker
bookkeeping, filesystem paths, and equivalent helper command spellings are
normalized.

Run just this corpus with:

```bash
ruby -Ilib test/popular_configs_equivalence_test.rb
```
