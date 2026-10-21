# Vision

## What tmux.rb should be

tmux.rb should make sophisticated tmux configuration feel like ordinary,
readable Ruby without putting Ruby in tmux's rendering hot path.

Users describe options, bindings, plugins, and dynamic formats with a small
Ruby DSL. tmux.rb compiles that source into deterministic, native tmux
configuration. Once loaded, tmux evaluates its own formats and does not need a
resident Ruby process.

The intended experience is something like the sketch below. It is
aspirational: `window_status`, `color`, and `when_` are not current API; see
the README for what exists today.

```ruby
Tmux.configure do
  prefix "C-s"

  window_status do
    style fg: color.blue, bg: color.dark
    value window.index

    when_(window.zoomed?) do
      text " (zoomed)"
    end
  end
end
```

instead of maintaining deeply nested `#{...}` expressions and manually
escaping delimiters.

## Principles

### Compile, do not interpret at runtime

Ruby runs during generation, validation, or installation. Generated files use
native tmux commands and formats so status updates remain fast and portable.

### Make invalid states difficult to express

Formats are represented by an abstract syntax tree. Conditional branches,
styles, commands, and variable expansions are structured nodes rather than
fragments joined by hand. The compiler owns tmux quoting and nested-format
escaping.

### Preserve access to tmux

The DSL should expose good abstractions without hiding tmux itself. New tmux
features should remain usable through typed primitives and a clearly marked
raw escape hatch.

### Generate deterministic output

The same Ruby source and tmux.rb version should produce byte-identical output.
This makes generated configuration reviewable in Git and suitable for golden
tests.

### Treat installation as a safety boundary

Generation must not silently reload or replace a user's live configuration.
The eventual workflow should separate these operations:

```text
tmux.rb build   config.rb --output tmux.conf
tmux.rb check   config.rb
tmux.rb diff    config.rb ~/.tmux.conf
tmux.rb install config.rb ~/.tmux.conf
```

Installation should validate against an isolated tmux server, write
atomically, retain a recoverable previous copy, and reload only when explicitly
requested.

### Treat configuration as trusted code

A configuration is Ruby, and building it runs it. tmux.rb isolates each file's
constants in an anonymous module for tidiness, not security, and says so
plainly rather than implying a sandbox.

## Real-world fixtures

Two kinds of real configuration keep the DSL honest:

- `examples/author_config.rb`, the author's complete configuration: bindings
  and multi-command bindings, compatibility branches for older tmux versions,
  shared color palettes, structured status, window, and pane-border formats,
  format substitutions, TPM plugins, and tmux-ai-attn integration.
  Its output is pinned byte-for-byte, and its window tabs are rendered by tmux
  across every attention state.
- `examples/popular_configs`, ten ports of well-known public configurations.
  Each is loaded beside its upstream original into isolated tmux servers, and
  their normalized options, hooks, environment, and key tables must match.

## Milestones

1. **Format compiler (complete)** — text, variables, styles, expansion,
   expressions, and conditional branches with correct escaping.
2. **Configuration compiler (complete)** — options, environment, sources,
   commands, bindings, shell predicates, and user/plugin options.
3. **Validation (complete)** — parse-only checks on an isolated tmux server and
   live isolated tests for dynamic format behavior.
4. **Golden migration (complete)** — a complete real configuration and ten
   public ports reproduce their hand-written equivalents, compared through
   isolated servers' effective options, hooks, environment, and keys.
5. **Safe workflow (partially complete)** — build, check, and diff exist;
   explicit atomic installation remains intentionally deferred.
6. **Reusable library (in progress)** — private internals, context-aware
   escaping verified against tmux, diagnostics that point at the offending
   configuration line, and gem packaging are in place; documenting extension
   points remains.

## Deferred ideas

Small refinements intentionally left until a real need appears:

- Per-side flag padding (`pl:`/`pr:`) alongside the symmetric `p:`. The
  powerline flag/segment helpers currently pad both sides of `content:` equally
  (`p:`, a space count); independent left/right control can be added later if a
  layout calls for it.

## Non-goals

- Running Ruby once per status refresh.
- Reimplementing tmux or evaluating live pane state in Ruby.
- Hiding generated configuration from users.
- Automatically modifying or restarting a live tmux server during compilation.
- Supporting tmux releases before 3.2, which escape and expand formats
  differently.

## Definition of success

tmux.rb succeeds when a complex configuration is easier to understand and
change in Ruby, while the generated tmux configuration remains fast,
inspectable, predictable, and operationally indistinguishable from a carefully
handwritten one.
