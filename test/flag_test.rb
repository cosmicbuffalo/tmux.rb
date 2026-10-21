require_relative "test_helper"

# Powerline flags: named edge glyphs, the fg/bg separator swap, self-contained
# badges (flags) vs open chain pieces (segments), and content padding.
class FlagTest < Minitest::Test
  L = "\u{e0b2}"  # left-pointing triangle
  R = "\u{e0b0}"  # right-pointing triangle

  def test_named_glyphs_resolve
    assert_equal 0xE0B2, Tmux::Glyph[:left_triangle].ord
    assert_equal 0xE0B0, Tmux::Glyph::RIGHT_TRIANGLE.ord
    assert_raises(Tmux::Error) { Tmux::Glyph[:nope] }
  end

  # --- switch: runtime conditional colors ----------------------------------

  def test_switch_builds_a_nested_conditional
    mode = Tmux.switch(Tmux.client_prefix => "#ff8800", Tmux.pane_in_mode => "#6a9955", else: "#2d2d30")
    assert_equal "\#{?client_prefix,#ff8800,\#{?pane_in_mode,#6a9955,#2d2d30}}", mode.to_s
  end

  def test_switch_requires_an_else
    assert_raises(Tmux::Error) { Tmux.switch(Tmux.client_prefix => "#ff8800") }
  end

  def test_switch_usable_as_a_color
    mode = Tmux.switch(Tmux.pane_in_mode => "#6a9955", else: "#2d2d30")
    fmt = Tmux.format { style bg: mode; text "x" }
    assert_equal "#[bg=\#{?pane_in_mode,#6a9955,#2d2d30}]x", fmt.to_tmux
  end

  # --- content & padding ---------------------------------------------------

  def test_variables_interpolate_as_their_long_form
    assert_equal "\#{session_name}", Tmux.session_name.to_s
    assert_equal "#S", Tmux.session_name.source
    assert_equal "\#{host_short}", Tmux.host_short.to_s
  end

  def test_array_content_mixes_literal_text_and_expressions
    fmt = Tmux.format { left_segment([Tmux.session_name, "@", Tmux.host], bg: "#00f", fg: "#000") }
    assert_equal "#[fg=#00f,bg=default]#{L}#[fg=#000,bg=#00f] #S@#H ", fmt.to_tmux
  end

  def test_string_content_keeps_interpolated_expressions_dynamic
    fmt = Tmux.format { left_segment("#{Tmux.session_name}@#{Tmux.host}", bg: "#00f", fg: "#000") }
    assert_equal "#[fg=#00f,bg=default]#{L}#[fg=#000,bg=#00f] \#{session_name}@\#{host} ", fmt.to_tmux
  end

  def test_content_is_padded_by_default
    fmt = Tmux.format { left_segment(bg: "#ffffff", fg: "#000000", content: "Z") }
    assert_equal "#[fg=#ffffff,bg=default]#{L}#[fg=#000000,bg=#ffffff] Z ", fmt.to_tmux
  end

  def test_content_may_be_the_first_positional_arg
    positional = Tmux.format { left_segment("Z", bg: "#ffffff", fg: "#000000") }.to_tmux
    keyword    = Tmux.format { left_segment(bg: "#ffffff", fg: "#000000", content: "Z") }.to_tmux
    assert_equal keyword, positional
  end

  def test_positional_expression_content
    fmt = Tmux.format { left_segment(Tmux.pane_mode, bg: "#6a9955", fg: "#000000") }
    assert_equal "#[fg=#6a9955,bg=default]#{L}#[fg=#000000,bg=#6a9955] \#{pane_mode} ", fmt.to_tmux
  end

  def test_pad_can_be_disabled
    fmt = Tmux.format { left_segment(bg: "#ffffff", fg: "#000000", content: "Z", p: 0) }
    assert_equal "#[fg=#ffffff,bg=default]#{L}#[fg=#000000,bg=#ffffff]Z", fmt.to_tmux
  end

  def test_pad_count_widens_both_sides
    fmt = Tmux.format { left_segment(bg: "#ffffff", fg: "#000000", content: "Z", p: 2) }
    assert_equal "#[fg=#ffffff,bg=default]#{L}#[fg=#000000,bg=#ffffff]  Z  ", fmt.to_tmux
  end

  def test_expression_content_is_appended_with_padding
    fmt = Tmux.format { left_segment(bg: "#6a9955", fg: "#000000", content: Tmux.pane_mode) }
    assert_equal "#[fg=#6a9955,bg=default]#{L}#[fg=#000000,bg=#6a9955] \#{pane_mode} ", fmt.to_tmux
  end

  def test_block_body_is_emitted_verbatim
    fmt = Tmux.format do
      left_segment(bg: "#6a9955", fg: "#000000") { text " "; append Tmux.pane_mode; text " " }
    end
    assert_equal "#[fg=#6a9955,bg=default]#{L}#[fg=#000000,bg=#6a9955] \#{pane_mode} ", fmt.to_tmux
  end

  # --- segments: one shared edge, no closing glyph -------------------------

  def test_segment_attrs_style_the_body_only_and_reset_after
    # a segment's edge stays a plain color transition; attrs apply to the body
    # and are reset afterward so they never leak past the chunk
    fmt = Tmux.format do
      left_segment(bg: "#ffffff", fg: "#000000", content: "Z", attrs: :bold, over: "#111111")
    end
    assert_equal "#[fg=#ffffff,bg=#111111]#{L}#[fg=#000000,bg=#ffffff,bold] Z #[nobold]", fmt.to_tmux
  end

  # Terminals draw bold text in a named color's bright variant, so a bold edge
  # glyph would differ in color from the flag's body.
  def test_flag_attrs_style_the_content_but_not_the_edges
    fmt = Tmux.format { left_flag(bg: "#ffffff", fg: "#000000", content: "Z", attrs: :bold) }
    assert_includes fmt.to_tmux, "#[fg=#ffffff,bg=default]#{L}"
    refute_match(/bold\]#{L}/, fmt.to_tmux)
  end

  def test_attrs_do_not_leak_after_a_segment
    fmt = Tmux.format do
      left_segment(bg: "#111", fg: "#fff", content: "a", attrs: :bold)
      text "after"
    end
    assert fmt.to_tmux.end_with?("#[nobold]after"), fmt.to_tmux
  end

  def test_over_defaults_to_the_previous_segments_bg
    fmt = Tmux.format do
      left_segment(bg: "#111", fg: "#fff", content: "a")
      left_segment(bg: "#222", fg: "#fff", content: "b")
    end
    # first segment's edge sits over default; the second's over the first's bg
    assert_includes fmt.to_tmux, "#[fg=#111,bg=default]"
    assert_includes fmt.to_tmux, "#[fg=#222,bg=#111]"
  end

  def test_right_segment_puts_the_glyph_after_the_content
    fmt = Tmux.format { right_segment(bg: "#2d2d30", fg: "#ffffff", content: "x") }
    assert_equal "#[fg=#ffffff,bg=#2d2d30] x #[fg=#2d2d30,bg=default]#{R}", fmt.to_tmux
  end

  # --- flags: self-contained by default (both edges) -----------------------

  def test_left_flag_is_self_contained_by_default
    fmt = Tmux.format { left_flag(bg: "#ffffff", fg: "#000000", attrs: :bold, content: "Z") }
    assert_equal(
      "#[fg=#ffffff,bg=default]#{L}" \
      "#[fg=#000000,bg=#ffffff,bold] Z " \
      "#[nobold]#[fg=#ffffff,bg=default,reverse]#{L}#[noreverse]",
      fmt.to_tmux
    )
  end

  # The notch sits at the end opposite the point: the left end of a right flag.
  def test_right_flag_puts_its_notch_before_the_body
    fmt = Tmux.format { right_flag(bg: "#fff", fg: "#000", content: "x") }
    assert_equal "#[fg=#fff,bg=default,reverse]#{R}#[noreverse]#[fg=#000,bg=#fff] x #[fg=#fff,bg=default]#{R}",
      fmt.to_tmux
  end

  def test_left_flag_can_blend_into_a_segment_and_notch_into_the_default_background
    fmt = Tmux.format do
      left_segment "cmd", bg: :colour238, fg: :white
      left_flag "Z", bg: :white, fg: :black, attrs: :bold, notch_over: :default
      left_segment "next", bg: :blue, fg: :white
    end

    assert_includes fmt.to_tmux,
      "#[fg=white,bg=colour238]#{L}#[fg=black,bg=white,bold] Z " \
      "#[nobold]#[fg=white,bg=default,reverse]#{L}#[noreverse]" \
      "#[fg=blue,bg=default]#{L}"
  end

  def test_right_flag_can_use_different_backgrounds_for_its_notch_and_point
    fmt = Tmux.format do
      right_flag "Z", bg: :white, fg: :black, over: :blue, notch_over: :default
    end

    assert_equal "#[fg=white,bg=default,reverse]#{R}#[noreverse]" \
      "#[fg=black,bg=white] Z #[fg=white,bg=blue]#{R}", fmt.to_tmux
  end

  def test_notch_background_does_not_override_a_runtime_selected_entry_background
    fmt = Tmux.format do
      switch_style(Tmux.user_option(:alert) => {bg: :red}, else: {bg: :blue})
      left_flag "Z", bg: :white, fg: :black, notch_over: :default
    end

    with_tmux_server do |tmux|
      [["0", "blue"], ["1", "red"]].each do |value, background|
        tmux.call("set-option", "-g", "@alert", value)
        assert_equal "#[bg=#{background}]#[fg=white,bg=#{background}]#{L}" \
          "#[fg=black,bg=white] Z #[fg=white,bg=default,reverse]#{L}#[noreverse]",
          render(tmux, fmt)
      end
    end
  end

  # The notch is cut in the color behind the flag, so the next block's edge is
  # drawn over that color rather than the flag's.
  def test_a_block_after_a_flag_starts_from_the_color_behind_it
    fmt = Tmux.format do
      left_flag "Z", bg: :white, fg: :black, over: :colour235
      left_segment "nvim", bg: :colour238, fg: :white
    end
    assert_includes fmt.to_tmux, "#[fg=white,bg=colour235,reverse]#{L}#[noreverse]#[fg=colour238,bg=colour235]#{L}"
  end

  def test_flag_without_attrs_skips_the_reset
    fmt = Tmux.format { left_flag(bg: "#6a9955", fg: "#000000", content: "x") }
    assert_equal "#[fg=#6a9955,bg=default]#{L}#[fg=#000000,bg=#6a9955] x " \
      "#[fg=#6a9955,bg=default,reverse]#{L}#[noreverse]", fmt.to_tmux
  end

  def test_flag_with_close_false_matches_a_segment
    flag = Tmux.format { left_flag(bg: "#fff", fg: "#000", content: "x", close: false) }.to_tmux
    seg  = Tmux.format { left_segment(bg: "#fff", fg: "#000", content: "x") }.to_tmux
    assert_equal seg, flag
  end

  # --- chip: floating double-ended badge -----------------------------------

  def test_chip_has_a_left_edge_in_and_a_right_edge_out
    fmt = Tmux.format { chip("5", bg: "#ff8800", fg: "#000000") }
    assert_equal(
      "#[fg=#ff8800,bg=default]#{L}#[fg=#000000,bg=#ff8800] 5 " \
      "#[fg=#ff8800,bg=default]#{R}#[default]",
      fmt.to_tmux
    )
  end

  def test_chip_accepts_an_expression
    fmt = Tmux.format { chip(Tmux.pane_index, bg: "#111", fg: "#fff") }
    assert_equal "#[fg=#111,bg=default]#{L}#[fg=#fff,bg=#111] \#{pane_index} #[fg=#111,bg=default]#{R}#[default]", fmt.to_tmux
  end

  def test_chip_shapes_choose_complementary_left_and_right_edges
    {
      triangle: [L, R, :white, :blue],
      thin: ["\u{e0b3}", "\u{e0b1}", :blue, :default],
      round: ["\u{e0b6}", "\u{e0b4}", :white, :blue],
      round_thin: ["\u{e0b7}", "\u{e0b5}", :blue, :default],
      rslant: ["\u{e0ba}", "\u{e0bc}", :white, :blue],
      lslant: ["\u{e0be}", "\u{e0b8}", :white, :blue]
    }.each do |shape, (left, right, foreground, background)|
      fmt = Tmux.format { chip "x", bg: :blue, fg: :white, left: shape, right: shape }

      assert_equal "#[fg=blue,bg=default]#{left}#[fg=#{foreground},bg=#{background}] x " \
        "#[fg=blue,bg=default]#{right}#[default]", fmt.to_tmux, shape.to_s
    end
  end

  def test_chip_slants_can_be_mixed_independently
    [
      [:rslant, :lslant, "\u{e0ba}", "\u{e0b8}"],
      [:lslant, :rslant, "\u{e0be}", "\u{e0bc}"]
    ].each do |left_shape, right_shape, left, right|
      fmt = Tmux.format { chip "x", bg: :blue, fg: :white, left: left_shape, right: right_shape }

      assert_equal "#[fg=blue,bg=default]#{left}#[fg=white,bg=blue] x " \
        "#[fg=blue,bg=default]#{right}#[default]", fmt.to_tmux
    end
  end

  def test_flag_and_segment_shapes_follow_the_helper_direction
    {left_flag: "\u{e0b6}", left_segment: "\u{e0b6}",
     right_flag: "\u{e0b4}", right_segment: "\u{e0b4}"}.each do |helper, expected|
      fmt = Tmux.format { public_send(helper, "x", bg: :blue, fg: :white, glyph: :round) }

      assert_includes fmt.to_tmux, expected, helper.to_s
    end
  end

  def test_chip_accepts_literal_edge_glyphs
    fmt = Tmux.format { chip "x", bg: :blue, fg: :white, left: "<", right: ">" }

    assert_equal "#[fg=blue,bg=default]<#[fg=white,bg=blue] x " \
      "#[fg=blue,bg=default]>#[default]", fmt.to_tmux
  end

  def test_thin_chip_shares_its_background_with_its_edges_and_keeps_padding_configurable
    fmt = Tmux.format do
      chip "thin", bg: :cyan, fg: :black, over: :colour235, left: :thin, right: :thin, p: 0
    end

    assert_equal "#[fg=cyan,bg=colour235]\u{e0b3}#[fg=cyan,bg=colour235]thin" \
      "#[fg=cyan,bg=colour235]\u{e0b1}#[default]", fmt.to_tmux
  end

  def test_thin_chip_uses_the_same_runtime_background_for_its_edges_and_body
    background = Tmux.switch(Tmux.user_option(:dark) => :colour235, else: :colour236)
    fmt = Tmux.format do
      chip "thin", bg: :cyan, fg: :black, over: background, left: :thin, right: :thin
    end

    with_tmux_server do |tmux|
      [["0", "colour236"], ["1", "colour235"]].each do |value, color|
        tmux.call("set-option", "-g", "@dark", value)
        style = "#[fg=cyan,bg=#{color}]"
        assert_equal "#{style}\u{e0b3}#{style} thin #{style}\u{e0b1}#[default]", render(tmux, fmt)
      end
    end
  end

  def test_mixed_thin_and_solid_edges_keep_the_specified_body_colors
    fmt = Tmux.format { chip "mixed", bg: :cyan, fg: :black, left: :thin, right: :round }

    assert_includes fmt.to_tmux, "#[fg=black,bg=cyan] mixed "
  end

  def test_relative_glyph_shapes_require_a_side
    error = assert_raises(Tmux::Error) { Tmux::Glyph.resolve(:round) }
    assert_match(/needs a side/, error.message)
  end

  # --- shared behaviors ----------------------------------------------------

  def test_glyph_override
    fmt = Tmux.format { left_segment(bg: "#fff", fg: "#000", content: "x", glyph: :left_round) }
    assert_includes fmt.to_tmux, "\u{e0b6}"
  end

  def test_wrap_surrounds_the_block_body
    fmt = Tmux.format do
      wrap ->(x) { " (#{x}) " } do
        command "echo hi"
      end
    end
    assert_equal " (#(echo hi)#[default]) ", fmt.to_tmux
  end

  def test_wrap_body_can_restyle_before_the_suffix
    # anything the block emits lands between prefix and suffix, in order
    fmt = Tmux.format do
      wrap ->(x) { "[#{x}]" } do
        command "c"
        style fg: "white", bg: "black"
      end
    end
    assert_equal "[#(c)#[fg=white,bg=black]#[default]]", fmt.to_tmux
  end

  def test_wrap_restores_the_entry_style_after_the_body
    # the style active when wrap begins is re-asserted before the suffix, so a
    # command whose output ends in #[default] doesn't bleed into the wrapper
    fmt = Tmux.format do
      style fg: "white", bg: "black"
      wrap ->(x) { " (#{x}) " } do
        command "c"
      end
    end
    assert_equal "#[fg=white,bg=black] (#(c)#[fg=white,bg=black]) ", fmt.to_tmux
  end

  def test_wrap_restores_a_runtime_selected_style
    fmt = Tmux.format do
      switch_style(Tmux.pane_input_off => {fg: :red}, else: {fg: :blue})
      wrap "[", "]" do
        text "body:"
        if?(Tmux.client_prefix) { style fg: :white }
        text "value"
      end
    end

    selected = '#{?pane_input_off,#[fg=red],#[fg=blue]}'
    prefix = '#{?client_prefix,#[fg=white],#[fg=blue]}'
    assert_equal "#{selected}[#[fg=blue]body:#{prefix}value#{selected}]", fmt.to_tmux
  end

  def test_segment_uses_the_runtime_selected_background_as_its_edge_background
    fmt = Tmux.format do
      switch_style(Tmux.pane_input_off => {bg: :red}, else: {bg: :blue})
      left_segment "x", bg: :white, fg: :black
    end

    assert_includes fmt.to_tmux, '#[fg=white,bg=#{?pane_input_off,red,blue}]'
  end

  def test_commas_escape_inside_a_conditional
    fmt = Tmux.format do
      if?(Tmux.window_zoomed_flag) { left_flag(bg: "#ffffff", fg: "#000000", content: "Z") }
    end
    assert_includes fmt.to_tmux, "#[fg=#ffffff#,bg=default]"
  end

  def test_if_else_fluent_form
    fmt = Tmux.format do
      if?(Tmux.window_zoomed_flag) { text "Z" }.else { text "-" }
    end
    assert_equal "\#{?window_zoomed_flag,Z,-}", fmt.to_tmux
  end
end
