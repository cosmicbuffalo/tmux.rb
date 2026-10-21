require_relative "test_helper"

# Tmux.pane_border assembles left/centre/right zones (in that order, regardless
# of how they're written) into one aligned format; style(p:) { } pads a body.
class PaneBorderTest < Minitest::Test
  def test_left_and_right_zones
    fmt = Tmux.pane_border do
      left { text "L" }
      right { text "R" }
    end
    assert_equal "L#[default]#[align=right]R", fmt.to_tmux
  end

  def test_centre_zone
    fmt = Tmux.pane_border do
      left { text "L" }
      center { text "C" }
      right { text "R" }
    end
    assert_equal "L#[default]#[align=centre]C#[default]#[align=right]R", fmt.to_tmux
  end

  def test_zone_order_does_not_matter
    written_out_of_order = Tmux.pane_border do
      right { text "R" }
      center { text "C" }
      left { text "L" }
    end
    in_order = Tmux.pane_border do
      left { text "L" }
      center { text "C" }
      right { text "R" }
    end
    assert_equal in_order.to_tmux, written_out_of_order.to_tmux
  end

  def test_only_the_zones_given_are_emitted
    fmt = Tmux.pane_border { right { text "R" } }
    assert_equal "#[default]#[align=right]R", fmt.to_tmux
  end

  def test_style_block_applies_the_style_and_pads_the_body
    fmt = Tmux.format { style(fg: "white", p: 1) { append Tmux.pane_index } }
    assert_equal "#[fg=white] \#{pane_index} ", fmt.to_tmux
  end

  def test_style_block_without_padding
    fmt = Tmux.format { style(fg: "white") { text "x" } }
    assert_equal "#[fg=white]x", fmt.to_tmux
  end
end
