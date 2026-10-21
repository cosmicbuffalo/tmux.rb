require_relative "test_helper"

# Compiled strings are checked directly, then rendered by a throwaway tmux
# server so the escaping is proven against tmux itself.
class EscapingTest < Minitest::Test
  def test_text_is_literal_at_the_top_level
    format = Tmux.format { text "issue #1 ##W #S C#" }

    assert_equal "issue ##1 ####W ##S C##", format.to_tmux
    with_tmux_server { |tmux| assert_equal "issue #1 ##W #S C#", render(tmux, format) }
  end

  def test_text_is_literal_inside_branches
    format = Tmux.format { if?(Tmux.pane_active) { text "a}b, #c" } }

    assert_equal "\#{?pane_active,a#}b#, ##c,}", format.to_tmux
    with_tmux_server { |tmux| assert_equal "a}b, #c", render(tmux, format) }
  end

  # tmux runs strftime over the top level and again over each chosen branch.
  def test_text_percent_signs_survive_every_nesting_level
    format = Tmux.format do
      text "50% "
      if?(Tmux.pane_active) do
        text "%H "
        if?(Tmux.pane_active) { text "%S%" }
      end
    end

    assert_equal "50%% \#{?pane_active,%%%%H \#{?pane_active,%%%%%%%%S%%%%%%%%,},}", format.to_tmux
    with_tmux_server { |tmux| assert_equal "50% %H %S%", render(tmux, format) }
  end

  def test_strftime_keeps_its_codes_and_escapes_structure
    format = Tmux.format do
      strftime "%Y,"
      if?(Tmux.pane_active) { strftime "%Y," }
    end

    assert_equal "%Y,\#{?pane_active,%Y#,,}", format.to_tmux
    with_tmux_server do |tmux|
      year = Time.now.year.to_s
      assert_equal "#{year},#{year},", render(tmux, format)
    end
  end

  def test_text_parts_interleave_literal_text_and_expressions
    format = Tmux.format { if?(Tmux.pane_active) { text "[", Tmux.session_name, "]," } }

    assert_equal "\#{?pane_active,[#S]#,,}", format.to_tmux
    with_tmux_server { |tmux| assert_equal "[verify],", render(tmux, format) }
  end

  def test_text_keeps_interpolated_expressions_dynamic_and_the_rest_literal
    format = Tmux.format do
      text " #{Tmux.window_index} "
      if?(Tmux.pane_active) { text "[#{Tmux.session_name}], 50% #1 #{Tmux.user_option(:probe).eq("a,b")}" }
    end

    assert_equal " \#{window_index} \#{?pane_active,[\#{session_name}]#, 50%%%% ##1 \#{==:\#{@probe},a#,b},}",
      format.to_tmux
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "a,b")
      assert_equal " 0 [verify], 50% #1 1", render(tmux, format)
    end
  end

  def test_text_rejects_styles_commands_and_unclosed_interpolation
    ["x#[fg=red]", "x#(date)", "x\#{oops"].each do |source|
      assert_raises(Tmux::Error) { Tmux.format { text source } }
    end
  end

  def test_literal_text_prints_format_code_as_written
    format = Tmux.format { text "literal \#{x} #(y)", literal: true }
    with_tmux_server { |tmux| assert_equal "literal \#{x} #(y)", render(tmux, format) }
  end

  def test_append_is_format_source_with_branch_structure_escaped
    format = Tmux.format { if?(Tmux.pane_active) { append "(\#{session_name},x)" } }

    assert_equal "\#{?pane_active,(\#{session_name}#,x),}", format.to_tmux
    with_tmux_server { |tmux| assert_equal "(verify,x)", render(tmux, format) }
  end

  def test_a_trailing_hash_in_appended_branch_source_does_not_eat_the_branch
    format = Tmux.format { if?(Tmux.pane_active) { append "a#" }.else { text "zz" } }

    with_tmux_server { |tmux| assert_equal "a#", render(tmux, format) }
  end

  def test_command_commas_and_braces_are_escaped_inside_branches
    format = Tmux.format { if?(Tmux.pane_active) { command "echo a,b}c \#{pane_id}" } }

    assert_equal "\#{?pane_active,#(echo a#,b#}c \#{pane_id}),}", format.to_tmux
  end

  def test_command_rejects_unbalanced_parentheses_anywhere
    ['echo "a)b"', 'echo "(a"', "echo \#{s/[(]/X/:pane_id}"].each do |command|
      error = assert_raises(Tmux::Error) { Tmux.format { command command } }
      assert_match(/unbalanced/, error.message)
    end
    Tmux.format { command "echo $(date) (x)" }
  end

  def test_matches_escapes_its_pattern
    expression = Tmux.user_option(:probe).matches('^a,b}#$')

    assert_equal '#{m/r:^a#,b#}##$,#{@probe}}', expression.source
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "a,b}#")
      assert_equal "1", render(tmux, Tmux.format { append expression })
    end
  end

  def test_substitute_escapes_arguments_and_avoids_delimiters_in_use
    expression = Tmux.user_option(:probe).substitute("a|b", "c,d")

    assert_equal "\#{s/a|b/c#,d/:@probe}", expression.source
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "xaybz")
      assert_equal "xc,dyc,dz", render(tmux, Tmux.format { append expression })
    end
  end

  def test_substitute_handles_regex_with_hash_and_brackets
    expression = Tmux.user_option(:probe).substitute('#\[[^]]*\]', "")

    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "#[fg=red]X#[default]")
      assert_equal "X", render(tmux, Tmux.format { append expression })
    end
  end

  def test_substitute_rejects_a_colon_tmux_cannot_escape
    error = assert_raises(Tmux::Error) { Tmux.pane_current_path.substitute("a:b", "x") }
    assert_match(/cannot contain ":"/, error.message)
  end

  def test_substitute_on_a_shorthand_variable_uses_its_name
    assert_equal "\#{s|x|y|:window_name}", Tmux.window_name.substitute("x", "y").source
  end

  def test_substitute_on_a_nested_expression_embeds_it
    nested = Tmux.user_option(:probe).substitute("a", "b").substitute("b", "c")

    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "abc")
      assert_equal "ccc", render(tmux, Tmux.format { append nested })
    end
  end

  def test_substitute_requires_a_free_delimiter
    error = assert_raises(Tmux::Error) do
      Tmux.user_option(:probe).substitute(Tmux::Expression::SUBSTITUTE_DELIMITERS.join, "")
    end
    assert_match(/delimiter/, error.message)
  end

  def test_comparison_operands_are_literal
    assert_equal "\#{==:\#{@probe},a#,b}", (Tmux.user_option(:@probe) == "a,b").source
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "a,b")
      assert_equal "1", render(tmux, Tmux.format { append(Tmux.user_option(:@probe) == "a,b") })
    end
  end

  # tmux's own #{!:...} only exists from 3.6.
  def test_bang_negates_on_every_tmux_version
    format = Tmux.format do
      text !Tmux.pane_active, !Tmux.user_option(:probe).eq("x")
    end

    assert_equal "\#{?pane_active,0,1}\#{?\#{==:\#{@probe},x},0,1}", format.to_tmux
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "x")
      assert_equal "00", render(tmux, format)
    end
  end

  def test_bang_negation_composes_with_logic_comparisons_and_double_negation
    format = load_source(<<~'RUBY')
      first = Tmux.user_option(:first)
      second = Tmux.user_option(:second)
      Tmux.format do
        if?(!first) { text "1" }.else { text "0" }
        if?(!!first) { text "1" }.else { text "0" }
        if?(!(first && second)) { text "1" }.else { text "0" }
        if?(!(first || second)) { text "1" }.else { text "0" }
        if?(!first && second) { text "1" }.else { text "0" }
        if?(!first.eq("1")) { text "1" }.else { text "0" }
      end
    RUBY

    with_tmux_server do |tmux|
      [0, 1].product([0, 1]).each do |a, b|
        tmux.call("set-option", "-g", "@first", a.to_s)
        tmux.call("set-option", "-g", "@second", b.to_s)
        expected = [a == 0, a == 1, !(a == 1 && b == 1), !(a == 1 || b == 1),
          a == 0 && b == 1, a != 1].map { |value| value ? "1" : "0" }.join
        assert_equal expected, render(tmux, format), "first=#{a}, second=#{b}"
      end
    end
  end

  def test_ordering_comparisons_are_numeric
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@probe", "10")
      probe = Tmux.user_option(:probe)
      results = [probe > 9, probe < 9, probe >= 10, probe <= 9]
      assert_equal %w[1 0 1 0], results.map { |expression| render(tmux, Tmux.format { append expression }) }
    end
  end

  def test_switch_values_escape_stray_structure
    format = Tmux.format { append Tmux.switch(Tmux.pane_active => "a,b", else: "c}") }

    assert_equal "\#{?pane_active,a#,b,c#}}", format.to_tmux
    with_tmux_server { |tmux| assert_equal "a,b", render(tmux, format) }
  end

  # #F and #D are window flags and pane id once tmux picks the branch.
  def test_switch_keeps_upper_case_hex_colors_intact
    color = Tmux.switch(Tmux.pane_active => "#FF8800", else: "#D0D0D0")

    assert_equal "\#{?pane_active,##FF8800,##D0D0D0}", color.source
    with_tmux_server do |tmux|
      assert_equal "#FF8800", render(tmux, Tmux.format { append color })
      assert_equal "#[fg=#FF8800]x", render(tmux, Tmux.format { style(fg: color) { text "x" } })
    end
  end

  def test_switch_inside_a_branch_still_renders
    format = Tmux.format do
      if?(Tmux.pane_active) { append Tmux.switch(Tmux.pane_active => "yes,1", else: "no") }
    end

    with_tmux_server { |tmux| assert_equal "yes,1", render(tmux, format) }
  end
end
