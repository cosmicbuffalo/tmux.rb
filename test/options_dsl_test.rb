require_relative "test_helper"

# Scoped and nested option names keep the same native tmux behavior.
class OptionsDslTest < Minitest::Test
  def compile(&block)
    Tmux.configure(&block).to_tmux
  end

  def test_scalar_leaf
    assert_equal %(set-option -g status-position "top"\n),
      compile { global.status.position = :top }
  end

  def test_leaf_that_is_also_a_namespace
    # `status.left` is assignable (the format) AND navigable (.length) — both
    # doors write to the same status-left* option family.
    assert_equal <<~CONF, compile { global.status.left = "fmt"; global.status.left.length = 100 }
      set-option -g status-left "fmt"
      set-option -g status-left-length 100
    CONF
  end

  def test_atomic_compound_style
    assert_equal %(set-option -g status-left-style "bg=default,fg=white,none"\n),
      compile { global.status.left.style = {bg: :default, fg: :white, attrs: :none} }
  end

  def test_status_and_clock_option_families
    output = compile do
      global.status = true
      global.status.interval = 5
      global.status.justify = :left
      global.status.style = {bg: :default, fg: :white}
      window.status.separator = " "
      window.clock.colour = :white
      window.clock.hour_format = 24
    end

    assert_equal <<~CONF, output
      set-option -g status on
      set-option -g status-interval 5
      set-option -g status-justify "left"
      set-option -g status-style "bg=default,fg=white"
      set-option -gw window-status-separator " "
      set-option -gw clock-mode-colour "white"
      set-option -gw clock-mode-style 24
    CONF
  end

  def test_append_operator_maps_to_dash_a
    assert_equal %(set-option -sa terminal-overrides ",*:clipboard:external"\n),
      compile { server.terminal_overrides << ",*:clipboard:external" }
  end

  def test_unset_maps_to_dash_u
    assert_equal %(set-option -gu status-left\n),
      compile { global.status.left.unset }
  end

  def test_window_scope_and_flat_name
    # window.mode_keys -> the flat name "mode-keys" (no window- prefix), set -w.
    assert_equal %(set-option -gw mode-keys "vi"\n),
      compile { window.mode_keys = :vi }
  end

  def test_ordering_is_preserved_and_not_collapsed
    # Repeated sets must survive as ordered nodes (fidelity), not a keyed map.
    assert_equal <<~CONF, compile { global.status.position = :top; global.status.position = :bottom }
      set-option -g status-position "top"
      set-option -g status-position "bottom"
    CONF
  end

  def test_flat_names_coexist_with_nested_names
    out = compile do
      global.status.position = :top
      global.history_limit = 10_000
    end
    assert_equal <<~CONF, out
      set-option -g status-position "top"
      set-option -g history-limit 10000
    CONF
  end

  def test_unknown_option_raises
    assert_raises(Tmux::Error) { compile { global.status.nonsense = 1 } }
  end

  def test_setting_a_namespace_raises
    assert_raises(Tmux::Error) { compile { global.pane = :x } }
  end

  def test_unset_on_a_namespace_raises
    assert_raises(Tmux::Error) { compile { window.pane.unset } }
  end

  def test_use_imports_a_components_config
    component = Object.new
    def component.to_config = Tmux.configure { global.history_limit = 5000 }
    assert_equal %(set-option -g history-limit 5000\n), compile { use component }
  end
end
