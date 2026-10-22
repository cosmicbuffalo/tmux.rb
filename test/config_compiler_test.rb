require_relative "test_helper"

class ConfigCompilerTest < Minitest::Test
  def test_compiles_options_bindings_and_sources
    config = Tmux.configure do
      global.status_position = :top
      global.mouse = true
      server.escape_time = 0
      server.terminal_overrides << ',xterm*:sitm=\E[3m'
      window.mode_keys = :vi
      global[:@example_flag] = "yes"
      bind "r", "source-file ~/.tmux.conf"
      source "~/.config/tmux/extra.conf"
    end

    assert_equal <<~TMUX, config.to_tmux
      set-option -g status-position "top"
      set-option -g mouse on
      set-option -s escape-time 0
      set-option -sa terminal-overrides ",xterm*:sitm=\\\\E[3m"
      set-option -gw mode-keys "vi"
      set-option -g @example_flag "yes"
      bind-key "r" source-file ~/.tmux.conf
      source-file "~/.config/tmux/extra.conf"
    TMUX
  end

  def test_compiles_shell_branches
    config = Tmux.configure do
      success = -> { global.status = true }
      failure = -> { global.status = false }
      if?(shell("true"), &success).else(&failure)
    end

    assert_equal <<~'TMUX', config.to_tmux
      if-shell "true" {
        set-option -g status on
      } {
        set-option -g status off
      }
    TMUX
  end

  def test_shell_condition_accepts_a_success_block
    block_form = Tmux.configure { if?(shell("true")) { global.status = true } }.to_tmux
    assert_equal "if-shell \"true\" {\n  set-option -g status on\n}\n", block_form
  end

  def test_shell_condition_accepts_an_else_block
    config = Tmux.configure do
      if?(shell("true")) { global.status = true }.else { global.status = false }
    end
    assert_equal "if-shell \"true\" {\n  set-option -g status on\n} {\n  set-option -g status off\n}\n", config.to_tmux
  end

  def test_shell_condition_supports_nested_blocks
    config = Tmux.configure do
      if?(shell("command -v first")) do
        global.default_shell = "first"
      end.else do
        if?(shell("command -v second")) do
          global.default_shell = "second"
        end
      end
    end

    assert_equal <<~'TMUX', config.to_tmux
      if-shell "command -v first" {
        set-option -g default-shell "first"
      } {
        if-shell "command -v second" {
          set-option -g default-shell "second"
        }
      }
    TMUX
  end

  def test_binding_flags
    config = Tmux.configure do
      bind "M-h", "select-pane -L", no_prefix: true
      bind "m", "select-layout main-horizontal", repeat: true, note: "Main horizontal"
      unbind "C-Left", no_prefix: true
    end

    assert_equal <<~TMUX, config.to_tmux
      bind-key -n "M-h" select-pane -L
      bind-key -r -N "Main horizontal" "m" select-layout main-horizontal
      unbind-key -n "C-Left"
    TMUX
  end

  def test_config_chain_selects_the_first_matching_shell_or_format_condition
    config = Tmux.configure do
      if?(Tmux.user_option(:@first) == "yes") do
        global[:@chosen] = "first"
      end.elsif?(shell('test "#{@second}" = yes')) do
        global[:@chosen] = "second"
      end.elsif?(Tmux.raw('#{==:#{@third},yes}')) do
        global[:@chosen] = "third"
      end.elsif?(shell('test "#{@fourth}" = yes')) do
        global[:@chosen] = "fourth"
      end.else do
        global[:@chosen] = "fallback"
      end
    end

    %w[first second third fourth fallback].each do |winner|
      # Later checks also succeed, so a match must stop the chain.
      names = %w[first second third fourth]
      settings = names.map.with_index do |name, index|
        value = index >= (%w[first second third fourth fallback].index(winner)) ? "yes" : "no"
        "set-option -g @#{name} #{value}\n"
      end.join
      with_tmux_server(settings + config.to_tmux) do |tmux|
        assert_equal winner, tmux.call("show-options", "-gqv", "@chosen").chomp
      end
    end
  end

  def test_shell_checks_are_deferred_and_unreached_checks_do_not_run
    Dir.mktmpdir do |directory|
      marker = File.join(directory, "ran")
      check = Tmux.shell("touch #{marker}")
      config = Tmux.configure do
        if?(shell("true")) { global[:@chosen] = "first" }
          .elsif?(check) { global[:@chosen] = "second" }
          .else { global[:@chosen] = "fallback" }
      end
      source = config.to_tmux
      refute_path_exists marker
      with_tmux_server(source) do |tmux|
        assert_equal "first", tmux.call("show-options", "-gqv", "@chosen").chomp
        refute_path_exists marker
      end
    end
  end

  def test_config_chain_captures_each_branch_once_and_keeps_helper_scope
    calls = []
    config = Tmux.configure do
      def label(name) = global[:@chosen] = name
      @fallback = "fallback"
      if?(shell("false")) { calls << :first; label("first") }
        .elsif?(shell("true")) { calls << :second; label("second") }
        .else { calls << :fallback; label(@fallback) }
    end

    config.to_tmux
    config.to_tmux
    assert_equal %i[first second fallback], calls
    with_tmux_server(config.to_tmux) do |tmux|
      assert_equal "second", tmux.call("show-options", "-gqv", "@chosen").chomp
    end
  end

  def test_shell_background_flag_is_preserved_for_each_branch
    config = Tmux.configure do
      if?(shell("first", background: true)) { blank }
        .elsif?(shell("second", background: true)) { blank }
    end
    assert_includes config.to_tmux, 'if-shell -b "first" {'
    assert_includes config.to_tmux, 'if-shell -b "second" {'
  end

  def test_config_chain_rejects_elsif_after_else_and_missing_elsif_block
    assert_raises(Tmux::Error) do
      Tmux.configure { if?(shell("true")) { blank }.else { blank }.elsif?(shell("false")) { blank } }
    end
    assert_raises(Tmux::Error) do
      Tmux.configure { if?(shell("true")) { blank }.elsif?(shell("false")) }
    end
  end

  def test_config_condition_rejects_ruby_booleans_and_shell_conditions_in_formats
    assert_raises(Tmux::Error) { Tmux.configure { if?(true) { blank } } }
    assert_raises(Tmux::Error) { Tmux.format { if?(Tmux.shell("true")) { text "yes" } } }
  end

  def test_binding_rejects_ambiguous_root_table
    error = assert_raises(Tmux::Error) do
      Tmux.configure { bind "x", "display-message x", table: :root, no_prefix: true }
    end

    assert_match(/cannot combine/, error.message)
  end

  def test_binding_command_blocks_compile_sequences_and_copy_mode_actions
    config = Tmux.configure do
      bind "WheelUpPane", table: "copy-mode-vi" do
        select_pane
        copy_mode :clear_selection, target: "{mouse}"
        copy_mode :scroll_up, target: "{mouse}", count: 5
      end
    end

    assert_equal <<~'TMUX', config.to_tmux
      bind-key -T "copy-mode-vi" "WheelUpPane" select-pane \; send-keys -t "{mouse}" -X clear-selection \; send-keys -t "{mouse}" -X -N 5 scroll-up
    TMUX
  end

  def test_binding_command_blocks_can_reload_a_ruby_config
    config = Tmux.configure do
      def reload_config
        load_config "~/.config/tmux/tmux.rb", message: "tmux reloaded"
      end

      bind "r", reload_config
    end

    assert_equal <<~'TMUX', config.to_tmux
      bind-key "r" run-shell "tmux.rb load -S \"#{socket_path}\" \\~/.config/tmux/tmux.rb" \; display-message "tmux reloaded"
    TMUX
  end

  def test_binding_command_blocks_build_display_menus
    config = Tmux.configure do
      bind "Space" do
        display_menu title: "Quick Actions" do
          item "Horizontal Split", key: "h", command: "split-window -v"
          separator
          item "Kill Pane", key: "x" do
            command :kill_pane
          end
        end
      end
    end

    assert_equal <<~'TMUX', config.to_tmux
      bind-key "Space" display-menu -T "Quick Actions" "Horizontal Split" "h" "split-window -v" "" "Kill Pane" "x" "kill-pane"
    TMUX
  end

  def test_binding_rejects_a_command_and_block_together
    error = assert_raises(Tmux::Error) do
      Tmux.configure do
        bind("x", "display-message old") { command :display_message, "new" }
      end
    end

    assert_match(/either a command or a block/, error.message)
  end

  def test_binding_rejects_an_empty_command_block
    error = assert_raises(Tmux::Error) { Tmux.configure { bind("x") {} } }

    assert_match(/at least one command/, error.message)
  end

  def test_binding_chains_compile_named_commands
    config = Tmux.configure do
      bind("-").split(:vertical).cwd("some-dir")
      bind("|").split(:horizontal, cwd: :current, size: "30%")
      bind("c").new_window
      bind("C").new_window(name: "scratch").cwd(:current).select_pane(target: "{last}")
      bind("h", repeat: true).select_pane(:left)
      bind("<", repeat: true).resize_pane(:left, 10)
      bind("M-z", no_prefix: true, note: "Zoom the pane").zoom
      bind("r").source("~/.tmux.conf").display_message("reloaded")
      bind("x").kill_pane
      bind("X", table: "prefix").kill_window
    end

    assert_equal <<~'TMUX', config.to_tmux
      bind-key "-" split-window -v -c "some-dir"
      bind-key "|" split-window -h -l "30%" -c "#{pane_current_path}"
      bind-key "c" new-window
      bind-key "C" new-window -n "scratch" -c "#{pane_current_path}" \; select-pane -t "{last}"
      bind-key -r "h" select-pane -L
      bind-key -r "<" resize-pane -L 10
      bind-key -n -N "Zoom the pane" "M-z" resize-pane -Z
      bind-key "r" source-file "~/.tmux.conf" \; display-message "reloaded"
      bind-key "x" kill-pane
      bind-key -T "prefix" "X" kill-window
    TMUX
  end

  def test_split_directions_have_short_names
    short = Tmux.configure do
      bind("-").split(:v)
      bind("|").split(:h, cwd: :current)
    end
    long = Tmux.configure do
      bind("-").split(:vertical)
      bind("|").split(:horizontal, cwd: :current)
    end

    assert_equal long.to_tmux, short.to_tmux
  end

  def test_binding_chains_and_blocks_share_named_commands
    chained = Tmux.configure { bind("-").split(:vertical, cwd: :current).select_pane(:up) }
    blocked = Tmux.configure do
      bind "-" do
        split :vertical
        cwd :current
        select_pane :up
      end
    end

    assert_equal chained.to_tmux, blocked.to_tmux
  end

  def test_binding_chains_stay_in_place_and_inside_conditionals
    config = Tmux.configure do
      bind("a").new_window
      global.mouse = true
      if?(Tmux.host_short == "laptop") { bind("b").zoom }
    end

    assert_equal <<~'TMUX', config.to_tmux
      bind-key "a" new-window
      set-option -g mouse on
      if-shell -F "#{==:#h,laptop}" {
        bind-key "b" resize-pane -Z
      }
    TMUX
  end

  def test_binding_chains_load_into_tmux
    config = Tmux.configure do
      bind("-").split(:vertical).cwd(:current)
      bind("c").new_window(name: "scratch")
      bind("<", repeat: true).resize_pane(:left, 10)
    end

    with_tmux_server(config.to_tmux) do |tmux|
      keys = tmux.call("list-keys", "-T", "prefix")
      assert_match(/split-window -v -c "#\{pane_current_path\}"/, keys)
      assert_match(/new-window -n scratch/, keys)
      assert_match(/-r -T prefix\s+<\s+resize-pane -L 10/, keys)
    end
  end

  def test_binding_chain_errors
    errors = {
      -> { Tmux.configure { bind("q") } } => /bind "q" has no command/,
      -> { Tmux.configure { bind("q").zoom.cwd(:current) } } => /cwd must follow split or new_window/,
      -> { Tmux.configure { bind("q").split(:vertical, cwd: "a").cwd("b") } } => /already has a directory/,
      -> { Tmux.configure { bind("q").split(:sideways) } } => /:vertical \(:v\) or :horizontal \(:h\)/,
      -> { Tmux.configure { bind("q").select_pane(:north) } } => /:left, :right, :up, or :down/
    }
    errors.each do |build, message|
      assert_match message, assert_raises(Tmux::Error, &build).message
    end
  end

  def test_raw_format_condition_preserves_background_flag
    config = Tmux.configure do
      if?(Tmux.raw(%q{#{>=:#{version},3.2}}), background: true) do
        global.mouse = true
      end
    end

    assert_equal <<~'TMUX', config.to_tmux
      if-shell -b -F "#{>=:#{version},3.2}" {
        set-option -g mouse on
      }
    TMUX
  end

  def test_tmux_version_helpers_compile_to_format_conditions
    config = Tmux.configure do
      tmux_below("2.9") { global.status = false }
      tmux_from("3.2") { global.mouse = true }.else { global.mouse = false }
    end

    output = config.to_tmux
    assert_includes output, "%if '\#{<:\#{version},2.9}'\nset-option -g status off\n%endif\n"
    assert_match(/\A%if '\#{e\|>=:.*,3002}'\nset-option -g mouse on\n%else\nset-option -g mouse off\n%endif\n\z/,
      output.lines.drop(3).join)
  end

  # The conditions read #{version}; rendering them against a stand-in option
  # covers versions other than the one installed.
  def test_tmux_version_conditions_order_real_version_strings
    expected = {
      "3.0" => [false, true, false], "3.1c" => [true, true, false],
      "3.2" => [true, false, false], "3.5a" => [true, false, false],
      "3.10" => [true, false, true], "next-3.6" => [true, false, false],
      "master" => [true, false, true], "openbsd-7.5" => [true, false, true],
      "4.0" => [true, false, true]
    }
    builder = Tmux::ConfigBuilder.new
    conditions = [[:from, "3.1"], [:below, "3.2"], [:from, "3.10"]].map do |direction, version|
      builder.send(:version_condition, direction, version).gsub("version}", "@fake_version}")
    end

    with_tmux_server do |tmux|
      expected.each do |version, results|
        tmux.call("set-option", "-g", "@fake_version", version)
        actual = conditions.map { |condition| render(tmux, condition) == "1" }
        assert_equal results, actual, "tmux #{version}: from 3.1, below 3.2, from 3.10"
      end
    end
  end

  def test_tmux_version_gates_apply_on_the_running_server
    config = Tmux.configure do
      tmux_from("3.0") { global[:@from_three] = "yes" }
      tmux_below("3.0") { global[:@below_three] = "yes" }
      tmux_from("99.0") { global[:@future] = "yes" }.else { global[:@future] = "no" }
    end

    with_tmux_server(config.to_tmux) do |tmux|
      assert_equal "yes", tmux.call("show-options", "-gqv", "@from_three").chomp
      assert_equal "", tmux.call("show-options", "-gqv", "@below_three").chomp
      assert_equal "no", tmux.call("show-options", "-gqv", "@future").chomp
    end
  end

  def test_tmux_version_helpers_reject_malformed_versions
    error = assert_raises(Tmux::Error) { Tmux.configure { tmux_below("3") { blank } } }
    assert_match(/invalid tmux version/, error.message)
  end

  def test_conditional_bodies_are_tmux_command_blocks
    config = Tmux.configure do
      if?(shell("true")) do
        raw "set -g @first 1 # trailing comment"
        raw "# full-line comment"
        blank
        raw "set -g @second \\\n  2"
      end
    end

    assert_equal <<~'TMUX', config.to_tmux
      if-shell "true" {
        set -g @first 1 # trailing comment
        # full-line comment

        set -g @second \
          2
      }
    TMUX
  end

  # Comments, %if directives, and expand: false all survive inside a body,
  # including nested ones.
  def test_conditional_bodies_behave_like_top_level_configuration
    config = Tmux.configure do
      if?(shell("true")) do
        raw "set -g @first 1 # trailing comment"
        raw "set -g @second 2"
        global[:@literal].set("$HOME/x", expand: false)
        tmux_from("3.0") { global[:@directive] = "yes" }
        if?(shell("false")) { global[:@never] = "x" }.else { global[:@nested] = "a;b" }
      end
    end

    with_tmux_server(config.to_tmux) do |tmux|
      values = %w[@first @second @literal @directive @never @nested].map do |option|
        # tmux 3.4 prints a stored "$" as "\\$"; the value itself is unescaped.
        tmux.call("show-options", "-gqv", option).chomp.gsub("\\$", "$")
      end
      assert_equal ["1", "2", "$HOME/x", "yes", "", "a;b"], values
    end
  end

  def test_raw_keeps_continued_lines_in_one_command
    config = Tmux.configure { raw "set -g @a \\\n  1\nset -g @b 2" }

    assert_equal 2, config.nodes.size
    assert_equal "set -g @a \\\n  1\nset -g @b 2\n", config.to_tmux
  end

  def test_environment_names_and_key_tables_are_quoted
    config = Tmux.configure do
      environment "MY VAR", "x"
      unbind "y", table: "copy-mode-vi"
    end

    assert_equal <<~'TMUX', config.to_tmux
      set-environment -g "MY VAR" "x"
      unbind-key -T "copy-mode-vi" "y"
    TMUX
  end

  def test_else_cannot_be_given_twice
    error = assert_raises(Tmux::Error) do
      Tmux.configure { if?(shell("true")) { blank }.else { blank }.else { blank } }
    end
    assert_match(/already has an else/, error.message)
  end

  def test_generic_option_fallbacks_are_removed
    builder = Tmux::ConfigBuilder.new
    %i[option window_option server_option user_option unset_option format_option window_format if_shell].each do |method|
      refute_respond_to builder, method
    end
  end

  def test_preserves_user_option_punctuation
    config = Tmux.configure do
      global[:@example_flag] = "underscores"
      global["@example-flag"] = "hyphens"
      global["@already-prefixed"] = "prefix"
      global[:@literal_path].set("~/bin/$COMMAND", expand: false)
    end

    assert_equal <<~'TMUX', config.to_tmux
      set-option -g @example_flag "underscores"
      set-option -g @example-flag "hyphens"
      set-option -g @already-prefixed "prefix"
      set-option -g @literal_path "\~/bin/\$COMMAND"
    TMUX
  end

  def test_embeds_a_format
    config = Tmux.configure do
      global.status_left = Tmux.format do
        style fg: "white", bg: "black"
        append Tmux.variable(:session_name, shorthand: "#S")
      end
    end

    assert_equal 'set-option -g status-left "#[fg=white,bg=black]#S"' + "\n", config.to_tmux
  end

  def test_format_options_forward_compiler_options
    config = Tmux.configure do
      global.status_right.set(Tmux.format do
        command 'printf "$HOME"'
      end, expand: false)
      window.window_status_format << Tmux.format do
        append Tmux.window_index
      end
    end

    assert_equal <<~'TMUX', config.to_tmux
      set-option -g status-right "#(printf \"\$HOME\")"
      set-option -gwa window-status-format "#I"
    TMUX
  end
end
