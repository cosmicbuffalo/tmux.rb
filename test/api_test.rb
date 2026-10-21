require_relative "test_helper"
require "tmpdir"

class ApiTest < Minitest::Test
  def test_ruby_booleans_are_rejected_as_conditions
    active = Tmux.pane_active
    [true, false, nil].each do |condition|
      error = assert_raises(Tmux::Error) { Tmux.format { if?(condition) { text "x" } } }
      assert_match(/tmux variable or expression comparison/, error.message)
    end
    assert_raises(Tmux::Error) { Tmux.switch(true => "a", else: "b") }
    assert_raises(Tmux::Error) { active == nil }
    assert_raises(Tmux::Error) { Tmux.format { append Object.new } }
  end

  def test_append_splices_a_format
    inner = Tmux.format { style fg: :red; text "x" }
    outer = Tmux.format { append inner; text "y" }

    assert_equal "#[fg=red]xy", outer.to_tmux
  end

  def test_native_user_option_symbols_work_for_assignment_lookup_and_expansion
    expression = Tmux.user_option(:@my_plugin_segment)
    expansion = Tmux.format { expand_option :@my_plugin_segment }
    config = Tmux.configure do
      global[:@my_plugin_segment] = '[#{session_name}]'
      global.status.left = expansion
    end

    assert_equal '#{@my_plugin_segment}', expression.source
    assert_equal '@my_plugin_segment', expression.condition_source
    assert_equal '#{E:@my_plugin_segment}', expansion.to_tmux
    assert_equal Tmux.user_option(:my_plugin_segment).source, expression.source
    with_tmux_server(config.to_tmux) do |tmux|
      assert_equal '[#{session_name}]', render(tmux, Tmux.format { append expression })
      assert_equal '[verify]', render(tmux, '#{E:status-left}')
    end
  end

  def test_switch_is_available_in_config_and_nested_format_blocks
    alert = Tmux.user_option(:alert)
    colors = {alert => :red, else: :white}
    labels = {alert => "alert", else: "okay"}
    shared_color = Tmux.switch(colors)
    config = Tmux.configure do
      global[:@color] = switch(colors)
      if?(shell("true")) do
        global.status_left = Tmux.format do
          if?(Tmux.pane_active) { append switch(labels) }
        end
      end
    end

    with_tmux_server(config.to_tmux) do |tmux|
      [["0", "white", "okay"], ["1", "red", "alert"]].each do |value, color, label|
        tmux.call("set-option", "-g", "@alert", value)
        assert_equal color, render(tmux, shared_color.source)
        assert_equal color, render(tmux, '#{E:@color}')
        assert_equal label, render(tmux, '#{E:status-left}')
      end
    end
  end

  def test_switch_is_available_with_explicit_builder_parameters
    cases = {Tmux.client_prefix => :yellow, else: :white}
    chosen_color = nil
    format = Tmux.format do |f|
      chosen_color = f.switch(cases)
      f.style fg: chosen_color
      f.text "status"
    end
    config = Tmux.configure do |c|
      c.global.status.style = {fg: c.switch(cases)}
    end

    assert_instance_of Tmux::Expression, chosen_color
    assert_equal Tmux.switch(cases).source, chosen_color.source
    assert_equal '#[fg=#{?client_prefix,yellow,white}]status', format.to_tmux
    assert_equal "set-option -g status-style \"fg=\#{?client_prefix,yellow,white}\"\n", config.to_tmux
  end

  def test_helper_methods_and_instance_variables_reach_nested_config_blocks
    config = Tmux.configure do
      def accent = "colour37"
      @mouse = true

      tmux_from("3.0") { window.pane_border_style = "fg=#{accent}" }
      if?(shell("true")) { global.mouse = @mouse }.else { global.status_style = "fg=#{accent}" }
    end

    assert_includes config.to_tmux, %(set-option -gw pane-border-style "fg=colour37")
    assert_includes config.to_tmux, "  set-option -g mouse on"
    assert_includes config.to_tmux, %(  set-option -g status-style "fg=colour37")
  end

  def test_helper_methods_reach_nested_format_blocks
    format = Tmux.format do
      def label = text("[", Tmux.session_name, "]")
      if?(Tmux.pane_active) { label }
    end

    assert_equal "\#{?pane_active,[#S],}", format.to_tmux
  end

  # A block parameter keeps Ruby's scoping, so outer methods stay callable.
  def test_blocks_with_a_parameter_receive_the_builder
    config = Tmux.configure do |c|
      c.global.status_style = palette_style
      c.if?(c.shell("true")) { |branch| branch.global.mouse = true }
    end

    assert_equal %(set-option -g status-style "fg=white"\nif-shell "true" {\n  set-option -g mouse on\n}\n), config.to_tmux
  end

  def test_builder_methods_chain
    config = Tmux.configure do
      global.mouse = true
      blank.raw("bind x kill-pane")
      global[:@a] = 1
    end
    format = Tmux.format { text("a").append(Tmux.pane_index).reset_style.expand_option(:seg) }

    assert_equal "set-option -g mouse on\n\nbind x kill-pane\nset-option -g @a 1\n", config.to_tmux
    assert_equal "a\#{pane_index}#[default]\#{E:@seg}", format.to_tmux
  end

  def test_else_cannot_be_given_twice_in_a_format
    error = assert_raises(Tmux::Error) do
      Tmux.format { if?(Tmux.pane_active) { text "a" }.else { text "b" }.else { text "c" } }
    end
    assert_match(/already has an else/, error.message)
  end

  # A style block's colors and attributes end with the block.
  def test_a_style_block_restores_the_style_from_before_it
    format = Tmux.format do
      style fg: :black, bg: :red
      style(fg: :white, bg: :blue, attrs: :bold, p: 1) { text "in" }
      text "after"
    end

    assert_equal "#[fg=black,bg=red]#[fg=white,bg=blue,bold] in #[fg=black,bg=red,nobold]after", format.to_tmux
    with_tmux_server do |tmux|
      assert_equal "#[fg=black,bg=red]#[fg=white,bg=blue,bold] in #[fg=black,bg=red,nobold]after",
        render(tmux, format)
    end
  end

  def test_a_style_after_a_style_block_moves_straight_to_its_own_style
    format = Tmux.format do
      style(fg: :white, bg: :blue, attrs: :bold) { text "a" }
      style bg: :green
      text "b"
    end

    assert_equal "#[fg=white,bg=blue,bold]a#[bg=green,fg=default,nobold]b", format.to_tmux
  end

  def test_a_style_block_at_the_end_of_a_branch_is_restored_inside_it
    format = Tmux.format do
      style fg: :black
      if?(Tmux.pane_active) { style(fg: :red) { text "x" } }
      text "y"
    end

    assert_equal "#[fg=black]\#{?pane_active,#[fg=red]x#[fg=black],}y", format.to_tmux
  end

  def test_nested_style_blocks_each_restore_their_own_entry_style
    format = Tmux.format do
      style(fg: :red) do
        style(fg: :blue) { text "inner" }
        text "outer"
      end
      text "after"
    end

    assert_equal "#[fg=red]#[fg=blue]inner#[fg=red]outer#[fg=default]after", format.to_tmux
  end

  def test_style_accepts_attribute_names_and_rejects_missing_colors
    assert_equal "#[bold]#[bold,italics]",
      Tmux.format { style(:bold).style([:bold, :italics]) }.to_tmux
    assert_raises(Tmux::Error) { Tmux.format { style fg: nil } }
    assert_raises(Tmux::Error) { Tmux.format { style 42 } }
  end

  def test_formats_and_configs_compare_by_content
    assert_equal Tmux.format { text "a" }, Tmux.format { text "a" }
    assert_equal Tmux.configure { global.mouse = true }, Tmux.configure { global.mouse = true }
    assert_equal "a", Tmux.format { text "a" }.to_s
  end

  def test_top_level_helpers_in_configuration_files_reach_parameter_blocks
    Dir.mktmpdir do |directory|
      path = File.join(directory, "config.rb")
      File.write(path, <<~RUBY)
        def accent = "colour37"
        Tmux.configure { |c| c.global.status.style = "fg=\#{accent}" }
      RUBY

      assert_equal %(set-option -g status-style "fg=colour37"\n), Tmux.load_file(path).to_tmux
    end
  end

  def test_internal_classes_are_private
    %i[Escape FormatCompiler ConfigCompiler OptionNode ZoneBuilder].each do |name|
      assert_raises(NameError) { eval("Tmux::#{name}") }
    end
  end

  private

  def palette_style = "fg=white"
end
