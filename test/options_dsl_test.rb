require_relative "test_helper"
require "fileutils"

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

  def test_use_imports_a_components_config_under_a_header
    component = Object.new
    def component.to_config = Tmux.configure { global.history_limit = 5000 }
    assert_equal <<~TMUX, compile { use component }
      # --- Object (options_dsl_test.rb) ---
      set-option -g history-limit 5000
    TMUX
  end

  module Keys
    def self.to_config = Tmux.configure { bind "x", "kill-pane" }
  end

  def test_use_separates_parts_and_names_a_module_by_its_constant
    assert_equal <<~TMUX, compile { global.mouse = true; use Keys; use Keys }
      set-option -g mouse on

      # --- OptionsDslTest::Keys (options_dsl_test.rb) ---
      bind-key "x" kill-pane

      # --- OptionsDslTest::Keys (options_dsl_test.rb) ---
      bind-key "x" kill-pane
    TMUX
  end

  def test_use_names_a_file_outside_the_callers_directory_from_home
    Dir.mktmpdir("tmux-rb-use", Dir.home) do |directory|
      part = File.join(directory, "part.rb")
      File.write(part, "module UseOutsidePart\n  def self.to_config = Tmux.configure { global.mouse = true }\nend\n")
      load part
      header = compile { use UseOutsidePart }.lines.first
      assert_equal "# --- UseOutsidePart (~/#{part.delete_prefix("#{Dir.home}/")}) ---\n", header
    ensure
      Object.send(:remove_const, :UseOutsidePart) if defined?(UseOutsidePart)
    end
  end

  def test_use_in_a_configuration_file_names_parts_relative_to_that_file
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "parts"))
      File.write(File.join(directory, "parts/keys.rb"), "module UseFilePart\n  def self.to_config = Tmux.configure { bind \"x\", \"kill-pane\" }\nend\n")
      config = File.join(directory, "tmux.rb")
      File.write(config, %(require_relative "parts/keys"\nTmux.configure { use UseFilePart }\n))
      assert_equal <<~TMUX, Tmux.load_file(config).to_tmux
        # --- UseFilePart (parts/keys.rb) ---
        bind-key "x" kill-pane
      TMUX
    ensure
      Object.send(:remove_const, :UseFilePart) if defined?(UseFilePart)
    end
  end

  def test_append_splices_without_a_header
    assert_equal %(set-option -g mouse on\n), compile { append Tmux.configure { global.mouse = true } }
  end
end
