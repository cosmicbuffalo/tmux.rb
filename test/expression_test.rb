require_relative "test_helper"

class ExpressionTest < Minitest::Test
  def test_comparison_operators_render_string_equality_and_numeric_ordering
    number = Tmux.user_option(:@number)
    other = Tmux.user_option(:@other)
    comparisons = [number == other, number != other, number > other,
      number < other, number >= other, number <= other]
    comparisons.each { |comparison| assert_instance_of Tmux::Expression, comparison }
    format = Tmux.format { comparisons.each { |comparison| append comparison; text " " } }

    with_tmux_server do |tmux|
      [
        ["10", "9", %w[0 1 1 0 1 0]],
        ["9", "10", %w[0 1 0 1 0 1]],
        ["10", "10", %w[1 0 0 0 1 1]],
        ["01", "1", %w[0 1 0 0 1 1]]
      ].each do |a, b, expected|
        tmux.call("set-option", "-g", "@number", a)
        tmux.call("set-option", "-g", "@other", b)
        assert_equal expected, render(tmux, format).split, "number=#{a}, other=#{b}"
      end
    end
  end

  def test_comparisons_compose_with_logic_and_negation_in_a_conditional
    format = load_source(<<~'RUBY')
      number = Tmux.user_option(:@number)
      Tmux.format do
        if?(number > 1 && number <= 5 && !(number == 3)) { text "match" }.else { text "other" }
      end
    RUBY

    with_tmux_server do |tmux|
      [["0", "other"], ["2", "match"], ["3", "other"], ["5", "match"], ["6", "other"]].each do |value, expected|
        tmux.call("set-option", "-g", "@number", value)
        assert_equal expected, render(tmux, format)
      end
    end
  end

  def test_structural_equality_and_hashes_do_not_build_comparison_expressions
    active = Tmux.pane_active
    same = Tmux.pane_active
    prefix = Tmux.client_prefix

    assert active.eql?(same)
    refute active.eql?(prefix)
    refute active.eql?(Tmux.raw(active.source))
    assert_equal active.hash, same.hash
    assert_equal 2, {active => "old", same => "same", prefix => "prefix"}.size

    format = Tmux.format { if?(active) { text "x" } }
    equivalent = Tmux.format { if?(same) { text "x" } }
    different = Tmux.format { if?(prefix) { text "x" } }
    assert_equal format, equivalent
    assert_equal format.hash, equivalent.hash
    refute_equal format, different

    config = Tmux.configure { global[:@value] = active }
    equivalent = Tmux.configure { global[:@value] = same }
    different = Tmux.configure { global[:@value] = prefix }
    assert_equal config, equivalent
    assert_equal config.hash, equivalent.hash
    refute_equal config, different
  end

  def test_style_blocks_restore_distinct_expression_colors
    outer = Tmux.user_option(:@outer_color)
    inner = Tmux.user_option(:@inner_color)
    format = Tmux.format do
      style fg: outer
      style(fg: inner) { text "inner" }
      text "outer"
    end

    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@outer_color", "blue")
      tmux.call("set-option", "-g", "@inner_color", "red")
      assert_equal "#[fg=blue]#[fg=red]inner#[fg=blue]outer", render(tmux, format)
    end
  end

  def test_conditional_styles_keep_distinct_expression_backgrounds
    active = Tmux.user_option(:@active)
    first = Tmux.user_option(:@first_color)
    second = Tmux.user_option(:@second_color)
    format = Tmux.format do
      if?(active) { style bg: first }.else { style bg: second }
      left_segment "x", bg: :white, fg: :black
    end

    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@first_color", "blue")
      tmux.call("set-option", "-g", "@second_color", "red")
      [["0", "red"], ["1", "blue"]].each do |value, color|
        tmux.call("set-option", "-g", "@active", value)
        assert_equal "#[bg=#{color}]#[fg=white,bg=#{color}]\u{e0b2}#[fg=black,bg=white] x ", render(tmux, format)
      end
    end
  end
end
