require_relative "test_helper"

class ConditionalTest < Minitest::Test
  def test_standalone_if_is_a_format_that_can_be_inspected_and_extended
    first = Tmux.user_option(:first)
    second = Tmux.user_option(:second)
    third = Tmux.user_option(:third)
    captures = []
    label = Tmux.if?(first) { captures << :first; text "first" }
    initial_nodes = label.nodes

    assert_kind_of Tmux::Format, label
    assert_predicate initial_nodes, :frozen?
    assert_equal '#{?@first,first,}', label.to_tmux
    assert_same label, label.elsif?(second) { captures << :second; text "second" }
    assert_same label, label.elsif?(third) { captures << :third; text "third" }
    assert_same label, label.else { captures << :fallback; text "fallback" }
    assert_equal %i[first second third fallback], captures
    assert_equal [], initial_nodes.first.on_false

    equivalent = Tmux.format do
      if?(first) { text "first" }.elsif?(second) { text "second" }
        .elsif?(third) { text "third" }.else { text "fallback" }
    end
    assert_equal equivalent, label
    assert_equal label, equivalent
    assert_equal equivalent.hash, label.hash
    assert_equal 1, {equivalent => true, label => true}.size
    assert_equal equivalent.to_tmux, label.to_s
  end

  def test_standalone_if_supports_parameter_blocks_assignment_and_nested_escaping
    first = Tmux.user_option(:first)
    second = Tmux.user_option(:second)
    label = Tmux.if?(first) do |f|
      f.style fg: :red
      f.text "first, 50% #1"
    end.elsif?(second) do |f|
      f.style fg: :blue
      f.text "second, 50% #2"
    end.else do |f|
      f.text "fallback, 50% #3"
    end
    config = Tmux.configure do
      global.status.left = label
      global.status.right = Tmux.format do
        if?(Tmux.pane_active) { text "["; append label; text "]" }
      end
    end

    with_tmux_server(config.to_tmux) do |tmux|
      [
        [1, 1, "#[fg=red]first, 50% #1"],
        [0, 1, "#[fg=blue]second, 50% #2"],
        [0, 0, "fallback, 50% #3"]
      ].each do |a, b, expected|
        tmux.call("set-option", "-g", "@first", a.to_s)
        tmux.call("set-option", "-g", "@second", b.to_s)
        assert_equal expected, render(tmux, label)
        assert_equal expected, render(tmux, '#{E:status-left}')
        assert_equal "[#{expected}]", render(tmux, '#{E:status-right}')
      end
    end
  end

  def test_standalone_if_loads_as_a_configuration_file_result
    Dir.mktmpdir do |directory|
      path = File.join(directory, "conditional.rb")
      File.write(path, <<~RUBY)
        Tmux.if?(Tmux.pane_active) { text "active" }.else { text "inactive" }
      RUBY

      assert_equal '#{?pane_active,active,inactive}', Tmux.load_file(path).to_tmux
    end
  end

  def test_standalone_if_validates_conditions_and_branch_order
    assert_raises(Tmux::Error) { Tmux.if?(true) { text "bad" } }
    label = Tmux.if?(Tmux.pane_active) { text "active" }
    assert_raises(Tmux::Error) { label.elsif?(Tmux.client_prefix) }
    assert_raises(Tmux::Error) { label.else }
    label.else { text "inactive" }
    error = assert_raises(Tmux::Error) do
      label.elsif?(Tmux.client_prefix) { text "prefix" }
    end
    assert_match(/already has an else/, error.message)
    assert_raises(Tmux::Error) { label.else { text "again" } }
  end

  def test_negated_conditions_work_in_if_and_elsif_branches
    first = Tmux.user_option(:first)
    second = Tmux.user_option(:second)
    format = Tmux.format do
      if?(!first) { text "first, 50%" }
        .elsif?(!second) { text "second, 50%" }
        .else { text "fallback, 50%" }
    end

    with_tmux_server do |tmux|
      [[0, 0, "first"], [0, 1, "first"], [1, 0, "second"], [1, 1, "fallback"]].each do |a, b, label|
        tmux.call("set-option", "-g", "@first", a.to_s)
        tmux.call("set-option", "-g", "@second", b.to_s)
        assert_equal "#{label}, 50%", render(tmux, format)
      end
    end
  end

  def test_repeated_elsif_branches_render_the_first_match_and_capture_each_block_once
    first = Tmux.user_option(:first)
    second = Tmux.user_option(:second)
    third = Tmux.user_option(:third)
    captures = []
    format = Tmux.format do
      if?(first) do
        captures << :first
        text "first, 50% #1"
      end.elsif?(second) do
        captures << :second
        text "second, 50% #2"
      end.elsif?(third) do
        captures << :third
        text "third, 50% #3"
      end.else do
        captures << :fallback
        text "fallback, 50% #4"
      end
    end

    assert_equal %i[first second third fallback], captures
    with_tmux_server do |tmux|
      [
        [1, 1, 1, "first, 50% #1"],
        [0, 1, 1, "second, 50% #2"],
        [0, 0, 1, "third, 50% #3"],
        [0, 0, 0, "fallback, 50% #4"]
      ].each do |a, b, c, expected|
        {first: a, second: b, third: c}.each do |name, value|
          tmux.call("set-option", "-g", "@#{name}", value.to_s)
        end
        assert_equal expected, render(tmux, format)
      end
    end
  end

  def test_elsif_without_else_keeps_an_empty_fallback_and_accepts_parameter_blocks
    format = Tmux.format do |f|
      f.if?(Tmux.user_option(:first)) { |branch| branch.text "first" }
        .elsif?(Tmux.user_option(:second)) { |branch| branch.text "second" }
    end

    assert_equal '#{?@first,first,#{?@second,second,}}', format.to_tmux
    with_tmux_server do |tmux|
      assert_equal "", render(tmux, format)
      tmux.call("set-option", "-g", "@second", "1")
      assert_equal "second", render(tmux, format)
    end
  end

  def test_elsif_preserves_nested_conditional_styles_and_wrapper_fallbacks
    first = Tmux.user_option(:first)
    second = Tmux.user_option(:second)
    [true, false].each do |style_only|
      [true, false].each do |with_else|
        success = -> { style fg: :red }
        alternate = -> do
          style bg: :blue
          text "alternate, 50%" unless style_only
        end
        fallback = -> { style fg: :green }
        build = ->(chained) do
          Tmux.format do
            style fg: :white, bg: :black
            wrap "[", "]" do
              if chained
                branches = if?(first, &success).elsif?(second, &alternate)
                branches.else(&fallback) if with_else
              else
                if?(first, &success).else do
                  branches = if?(second, &alternate)
                  branches.else(&fallback) if with_else
                end
              end
              style(fg: :yellow) { text "body" }
              text "tail"
            end
            text "after"
          end
        end

        assert_equal build.call(false), build.call(true),
          "nested equivalence with style_only=#{style_only}, with_else=#{with_else}"
      end
    end
  end

  def test_elsif_rejects_a_missing_block_and_invalid_conditions
    error = assert_raises(Tmux::Error) do
      Tmux.format { if?(Tmux.pane_active) { text "a" }.elsif?(Tmux.client_prefix) }
    end
    assert_match(/\.elsif\? needs a block/, error.message)

    error = assert_raises(Tmux::Error) do
      Tmux.format { if?(Tmux.pane_active) { text "a" }.elsif?(true) { text "b" } }
    end
    assert_match(/tmux variable or expression comparison/, error.message)
  end

  def test_elsif_cannot_follow_else_and_the_final_else_cannot_be_repeated
    error = assert_raises(Tmux::Error) do
      Tmux.format do
        if?(Tmux.pane_active) { text "a" }.else { text "b" }
          .elsif?(Tmux.client_prefix) { text "c" }
      end
    end
    assert_match(/already has an else/, error.message)

    error = assert_raises(Tmux::Error) do
      Tmux.format do
        if?(Tmux.pane_active) { text "a" }.elsif?(Tmux.client_prefix) { text "b" }
          .else { text "c" }.else { text "d" }
      end
    end
    assert_match(/already has an else/, error.message)
  end
end
