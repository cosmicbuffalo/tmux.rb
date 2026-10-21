require_relative "test_helper"
require_relative "../examples/popular_configs/oh_my_tmux/profile"
require_relative "../examples/popular_configs/oh_my_tmux/runtime"

class OhMyTmuxPortTest < Minitest::Test
  SOURCE = File.expand_path(
    "../examples/popular_configs/oh_my_tmux/tmux.rb", __dir__
  )

  def test_profile_is_a_native_tmux_rb_config
    config = OhMyTmux.configure(source_path: SOURCE)
    generated = config.to_tmux

    assert_instance_of Tmux::Config, config
    refute_includes generated, "cut -c3-"
    refute_includes generated, "original.tmux.conf"
    assert_includes generated, "set-option -gw window-status-format"
    assert_includes generated, "runtime.rb metrics-loop"
  end

  def test_profile_customizes_the_palette_in_generated_formats_and_styles
    config = OhMyTmux.configure(source_path: SOURCE) do
      color 4, "#123456"
    end
    generated = config.to_tmux

    assert_includes generated, 'display-panes-colour "#123456"'
    assert_includes generated, "bg=#123456"
    refute_includes generated, 'display-panes-colour "#00afff"'
  end

  def test_profile_can_disable_current_path_retention_for_new_panes
    config = OhMyTmux.configure(source_path: SOURCE) do
      self.new_pane_retain_current_path = false
    end
    generated = config.to_tmux

    assert_includes generated, 'bind-key "-" split-window -v'
    refute_includes generated, 'bind-key "-" split-window -v -c'
    assert_match(/ h \{ split-window -h \}|"split-window -h"/, generated)
    refute_includes generated, "split-window -h -c"
  end

  def test_runtime_boolean_and_battery_bar_helpers
    assert OhMyTmuxRuntime.truthy?("enabled")
    refute OhMyTmuxRuntime.truthy?("disabled")

    empty = OhMyTmuxRuntime.battery_bar(0)
    full = OhMyTmuxRuntime.battery_bar(100)
    assert_equal 4, empty.count("◻")
    assert_equal 4, full.count("◼")
  end
end
