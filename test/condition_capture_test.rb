require_relative "test_helper"

class ConditionCaptureTest < Minitest::Test
  def test_capture_keeps_locals_precedence_negation_and_comparisons
    format = load_source(<<~'RUBY')
      active = Tmux.user_option(:@active)
      prefix = Tmux.user_option(:@prefix)
      count = Tmux.user_option(:@count)
      Tmux.if?(active && !prefix || count >= 2 && count <= 5) { text "yes" }
        .else { text "no" }
    RUBY

    with_tmux_server do |tmux|
      [0, 1].repeated_permutation(2) do |a, p|
        [1, 2, 5, 6].each do |n|
          {active: a, prefix: p, count: n}.each do |name, value|
            tmux.call("set-option", "-g", "@#{name}", value.to_s)
          end
          truth = (a == 1 && p == 0) || (n >= 2 && n <= 5)
          assert_equal truth ? "yes" : "no", render(tmux, format)
        end
      end
    end
  end

  def test_capture_supports_parentheses_comments_and_string_comparisons
    format = load_source(<<~'RUBY')
      command = Tmux.pane_current_command
      Tmux.if?(!(command == "vim" || # keep the next operand
        command == "nvim") && Tmux.pane_active) { text "yes" }
    RUBY

    assert_equal '#{?#{&&:#{?#{||:#{==:#{pane_current_command},vim},#{==:#{pane_current_command},nvim}},0,1},#{pane_active}},yes,}',
      format.to_tmux
  end

  def test_capture_builds_both_operands_once_instead_of_short_circuiting
    format = load_source(<<~'RUBY')
      calls = []
      reader = ->(name) { calls << name; Tmux.user_option(name) }
      result = Tmux.if?(reader.call(:@first) || reader.call(:@second)) { text "yes" }
      raise "wrong calls: #{calls}" unless calls == %i[@first @second]
      result
    RUBY

    assert_equal '#{?#{||:#{@first},#{@second}},yes,}', format.to_tmux
  end

  def test_capture_retains_helper_methods_and_instance_variable_scope
    format = load_source(<<~'RUBY')
      @active_condition = Tmux.pane_active
      def prefix_condition = Tmux.client_prefix
      Tmux.if?(@active_condition && prefix_condition) { text "yes" }
    RUBY

    assert_equal '#{?#{&&:#{pane_active},#{client_prefix}},yes,}', format.to_tmux
  end

  def test_loaded_files_automatically_capture_if_and_elsif_arguments
    format = load_source(<<~'RUBY')
      # Keep this comment and blank line in the evaluated file.

      active = Tmux.user_option(:@active)
      prefix = Tmux.user_option(:@prefix)
      mode = Tmux.user_option(:@mode)
      Tmux.format do |f|
        f.text "λ "
        f.if?(active && prefix) { |b| b.text "A" }
          .elsif?(!active || mode) { |b| b.text "B" }
          .else { |b| b.text "C" }
      end
    RUBY

    assert_equal 'λ #{?#{&&:#{@active},#{@prefix}},A,#{?#{||:#{?@active,0,1},#{@mode}},B,C}}',
      format.to_tmux
    with_tmux_server do |tmux|
      [0, 1].repeated_permutation(3) do |a, p, m|
        {active: a, prefix: p, mode: m}.each do |name, value|
          tmux.call("set-option", "-g", "@#{name}", value.to_s)
        end
        expected = if a == 1 && p == 1 then "A"
        elsif a == 0 || m == 1 then "B"
        else "C"
        end
        assert_equal "λ #{expected}", render(tmux, format)
      end
    end
  end

  def test_loaded_nested_config_formats_and_standalone_conditionals
    config = load_source(<<~'RUBY')
      active = Tmux.pane_active
      Tmux.configure do
        global.status.left = Tmux.if?(active && Tmux.client_prefix) { text "A" }
        global.status.right = Tmux.format do
          if?(active && Tmux.pane_index >= 2) { text "B" }
        end
      end
    RUBY

    assert_includes config.to_tmux, '#{&&:#{pane_active},#{client_prefix}}'
    assert_includes config.to_tmux, '#{&&:#{pane_active},#{e|>=:#{pane_index},2}}'
  end

  def test_loaded_files_leave_ordinary_ruby_logic_alone
    format = load_source(<<~'RUBY')
      calls = []
      false && calls << :unreachable
      Tmux.pane_active || calls << :also_unreachable
      raise "rewrote ordinary Ruby" unless calls.empty?
      Tmux.if?(Tmux.pane_active && Tmux.client_prefix) { text "A" }
    RUBY

    assert_equal '#{?#{&&:#{pane_active},#{client_prefix}},A,}', format.to_tmux
  end

  def test_loaded_config_chains_capture_logical_expressions_alongside_shell_checks
    config = load_source(<<~'RUBY')
      first = Tmux.user_option(:@first)
      second = Tmux.user_option(:@second)
      Tmux.configure do
        if?(first == "yes" && second == "yes") { global[:@chosen] = "both" }
          .elsif?(shell("false")) { global[:@chosen] = "shell" }
          .elsif?(first == "yes" || second == "yes") { global[:@chosen] = "one" }
          .else { global[:@chosen] = "neither" }
      end
    RUBY

    ["no", "yes"].repeated_permutation(2) do |first, second|
      settings = "set-option -g @first #{first}\nset-option -g @second #{second}\n"
      expected = if first == "yes" && second == "yes" then "both"
      elsif first == "yes" || second == "yes" then "one"
      else "neither"
      end
      with_tmux_server(settings + config.to_tmux) do |tmux|
        assert_equal expected, tmux.call("show-options", "-gqv", "@chosen").chomp
      end
    end
  end

  def test_switch_and_switch_style_capture_inline_keys_but_not_values
    format = load_source(<<~'RUBY')
      active = Tmux.user_option(:@active)
      prefix = Tmux.user_option(:@prefix)
      Tmux.format do
        color = switch(active && prefix => :red, else: :white)
        style fg: color
        append Tmux.switch({active || prefix => "yes", else: "no"})
        switch_style(active && !prefix => {fg: :blue}, else: {fg: :green})
        text "X"
        append switch(active => (false || "value"), else: "fallback")
      end
    RUBY

    with_tmux_server do |tmux|
      [0, 1].repeated_permutation(2) do |a, p|
        {active: a, prefix: p}.each do |name, value|
          tmux.call("set-option", "-g", "@#{name}", value.to_s)
        end
        fg = a == 1 && p == 1 ? "red" : "white"
        label = a == 1 || p == 1 ? "yes" : "no"
        next_fg = a == 1 && p == 0 ? "blue" : "green"
        tail = a == 1 ? "value" : "fallback"
        assert_equal "#[fg=#{fg}]#{label}#[fg=#{next_fg}]X#{tail}", render(tmux, format)
      end
    end
  end

  def test_reusable_conditional_helpers_are_captured_in_the_loaded_file
    config = load_source(<<~'RUBY')
      def label
        active = Tmux.pane_active
        Tmux.if?(active && Tmux.client_prefix) { text "A" }.else { text "B" }
      end
      Tmux.configure do |c|
        c.global.status.left = label
        c.global.status.right = label
      end
    RUBY

    assert_equal 2, config.to_tmux.scan('#{?#{&&:#{pane_active},#{client_prefix}},A,B}').length
  end

  def test_loader_preserves_trailing_source_and_no_final_newline
    assert_equal '#{?#{&&:#{pane_active},#{client_prefix}},A,}',
      load_source('Tmux.if?(Tmux.pane_active && Tmux.client_prefix) { text "A" } # tail').to_tmux
  end

  def test_capture_rejects_unsupported_blocks_safe_navigation_and_keyword_logic
    [
      'Tmux.if?(Tmux.pane_active && [1].map { Tmux.client_prefix }) { text "bad" }',
      'Tmux.if?(Tmux.pane_active && Tmux&.client_prefix) { text "bad" }',
      'Tmux.if?((Tmux.pane_active and Tmux.client_prefix)) { text "bad" }'
    ].each do |source|
      error = assert_raises(Tmux::Error) { load_source(source) }
      assert_match(/config\.rb:1:/, error.message)
    end
  end

  def test_capture_reports_parse_errors_with_source_location
    error = assert_raises(Tmux::Error) do
      load_source("# header\nTmux.if?(Tmux.pane_active && ) { text 'bad' }\n")
    end

    assert_match(/config\.rb:2:/, error.message)
  end

  def test_nested_conditional_arguments_do_not_overlap
    format = load_source(<<~'RUBY')
      Tmux.format do
        if?(Tmux.pane_active && Tmux.client_prefix) do
          if?(Tmux.pane_in_mode || Tmux.pane_input_off) { text "A" }
        end
      end
    RUBY

    assert_equal '#{?#{&&:#{pane_active},#{client_prefix}},#{?#{||:#{pane_in_mode},#{pane_input_off}},A,},}',
      format.to_tmux
  end

  def test_loader_keeps_original_error_lines_after_multiline_capture
    Dir.mktmpdir do |directory|
      path = File.join(directory, "condition.rb")
      File.write(path, <<~'RUBY')
        # λ leading comment

        Tmux.format do
          if?(Tmux.pane_active && # comment
              Tmux.client_prefix) { text "A" }
          raise "original line"
        end
      RUBY
      error = assert_raises(RuntimeError) { Tmux.load_file(path) }

      assert_equal "original line", error.message
      assert_match(/#{Regexp.escape(path)}:6:/, error.backtrace.first)
    end
  end

  def test_capture_rejects_unsupported_syntax_before_executing_it
    error = assert_raises(Tmux::Error) do
      load_source(<<~'RUBY')
        Tmux.if?((raise "must not execute") && (changed = Tmux.pane_active)) { text "bad" }
      RUBY
    end

    assert_match(/assignments and control flow/, error.message)
    error = assert_raises(Tmux::Error) do
      load_source(<<~'RUBY')
        Tmux.if?(Tmux.pane_active && (true ? Tmux.client_prefix : Tmux.pane_in_mode)) { text "bad" }
      RUBY
    end
    assert_match(/single expression/, error.message)
  end

  def test_capture_rejects_ruby_boolean_operands
    error = assert_raises(Tmux::Error) do
      load_source('Tmux.if?(Tmux.pane_active && true) { text "bad" }')
    end

    assert_match(/expected a tmux expression, got true/, error.message)
  end

  def test_condition_and_bitwise_operators_are_not_public_dsl
    refute_respond_to Tmux, :condition
    refute_respond_to Tmux::FormatBuilder.new, :condition
    refute_respond_to Tmux::ConfigBuilder.new, :condition
    refute_respond_to Tmux.pane_active, :&
    refute_respond_to Tmux.pane_active, :|
    assert_raises(NoMethodError) { Tmux.pane_active & Tmux.client_prefix }
    assert_raises(NoMethodError) { Tmux.pane_active | Tmux.client_prefix }
  end
end
