require_relative "test_helper"

class CompilerTest < Minitest::Test
  def test_compiles_text_styles_and_variables
    format = Tmux.format do
      style fg: "white", bg: "black"
      text " "
      append Tmux.variable(:window_name)
      reset_style
    end

    assert_equal '#[fg=white,bg=black] #{window_name}#[default]', format.to_tmux
  end

  def test_escapes_style_commas_inside_conditional_branches
    format = Tmux.format do
      if?(!Tmux.user_option(:flashing)) do
        style fg: "white", bg: "black"
      end
    end

    assert_equal '#{?#{?@flashing,0,1},#[fg=white#,bg=black],}', format.to_tmux
  end

  def test_combines_expressions
    format = load_source(<<~'RUBY')
      Tmux.format do
        if?(!(Tmux.user_option(:flash) && Tmux.user_option(:phase))) { text "off" }
      end
    RUBY

    assert_equal '#{?#{?#{&&:#{@flash},#{@phase}},0,1},off,}', format.to_tmux
  end

  def test_if_and_else_accept_reusable_branches_and_render_both_outcomes
    enabled = -> { style fg: :white, bg: :black; text "on, "; append Tmux.window_name }
    disabled = -> { style fg: :black, bg: :white; text "off, "; append Tmux.window_name }
    format = Tmux.format do
      if?(Tmux.user_option(:enabled), &enabled).else(&disabled)
    end

    assert_equal '#{?@enabled,#[fg=white#,bg=black]on#, #W,#[fg=black#,bg=white]off#, #W}',
      format.to_tmux
    with_tmux_server do |tmux|
      tmux.call("set-option", "-g", "@enabled", "1")
      assert_equal "#[fg=white,bg=black]on, editor", render(tmux, format)
      tmux.call("set-option", "-g", "@enabled", "0")
      assert_equal "#[fg=black,bg=white]off, editor", render(tmux, format)
    end
  end
end
