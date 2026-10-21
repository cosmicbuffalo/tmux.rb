require_relative "test_helper"

class DynamicOptionsTest < Minitest::Test
  Target = Tmux.const_get(:Target)
  Catalog = Tmux.const_get(:OptionCatalog)

  def test_previously_unlisted_options_use_the_scoped_dsl
    config = Tmux.configure do
      global.prefix2 = "C-s"
      server.copy_command = "pbcopy"
      window.monitor_bell = true
    end

    assert_equal <<~CONF, config.to_tmux
      set-option -g prefix2 "C-s"
      set-option -s copy-command "pbcopy"
      set-option -gw monitor-bell on
    CONF
  end

  def test_every_discovered_option_supports_a_flat_and_nested_accessor
    target = Target.current
    target.catalog.scopes.each do |scope, entries|
      config = Tmux.configure do |builder|
        root = builder.public_send(scope)
        entries.each_key { |name| root.public_send("#{name.tr('-', '_')}=", "value") }
      end
      nested = Tmux.configure do |builder|
        root = builder.public_send(scope)
        entries.each_key do |name|
          parts = name.split("-")
          parent = parts[0...-1].reduce(root) { |node, part| node.public_send(part) }
          parent.public_send("#{parts.last}=", "value")
        end
      end

      assert_equal entries.keys, config.nodes.map(&:name), scope
      assert_equal config.to_tmux, nested.to_tmux, scope
      assert config.nodes.all? { |node| node.scope == scope }
    end
  end

  def test_unknown_names_suggest_a_valid_option
    error = assert_raises(Tmux::Error) { Tmux.configure { global.prefxi2 = "C-s" } }

    assert_match(/unknown option "prefxi2"/, error.message)
    assert_includes error.message, Target.current.version
    assert_match(/did you mean "prefix2"/, error.message)
  end

  def test_wrong_scope_is_rejected_even_though_tmux_would_infer_it
    error = assert_raises(Tmux::Error) { Tmux.configure { window.escape_time = 10 } }

    assert_match(/not a window option/, error.message)
    assert_match(/use server.escape_time/, error.message)
  end

  def test_exact_names_arrays_and_custom_user_options
    config = Tmux.configure do
      global[:prefix2] = "C-s"
      server.user_keys[0] = "\e[5;30012~"
      global[:@my_plugin_segment] = "segment"
      global[:@my_plugin_segment] << " tail"
      global[:@my_plugin_segment].unset
    end

    assert_equal ["prefix2", "user-keys[0]", "@my_plugin_segment", "@my_plugin_segment", "@my_plugin_segment"],
      config.nodes.map(&:name)
    assert_includes config.to_tmux, 'set-option -s user-keys[0]'
    assert_includes config.to_tmux, 'set-option -ga @my_plugin_segment " tail"'
    assert_includes config.to_tmux, 'set-option -gu @my_plugin_segment'
    assert_raises(Tmux::Error) { Tmux.configure { server.user_keys[-1] = "bad" } }
    assert_raises(Tmux::Error) { Tmux.configure { global.prefix[0] = "C-s" } }
  end

  def test_custom_options_follow_the_selected_scope_and_do_not_change_the_live_server
    config = Tmux.configure do
      global[:@custom] = "session"
      window[:@custom] = "window"
      server[:@custom] = "server"
    end

    with_tmux_server(config.to_tmux) do |tmux|
      assert_equal "session", tmux.call("show-options", "-gv", "@custom").strip
      assert_equal "window", tmux.call("show-options", "-gwv", "@custom").strip
      assert_equal "server", tmux.call("show-options", "-sv", "@custom").strip
    end
  end

  def test_ruby_method_collisions_and_ergonomic_names_remain_usable
    config = Tmux.configure do |builder|
      scope = builder.target.catalog.scopes.fetch(:global).key?("display-panes-time") ? builder.global : builder.window
      scope.display.panes.time = 1000
      builder.server.set.clipboard = :external
      builder.window.clock.hour_format = 24
      builder.window[:clock_mode_colour] = :blue
      builder.global.status.left.set("$HOME", expand: false)
    end

    assert_equal %w[display-panes-time set-clipboard clock-mode-style clock-mode-colour status-left],
      config.nodes.map(&:name)
    assert_includes config.to_tmux, 'set-option -g status-left "\$HOME"'
  end

  def test_empty_arrays_are_not_lost_and_hooks_are_discovered
    catalog = Target.current.catalog

    assert catalog.scopes.fetch(:server).fetch("user-keys").fetch(:array)
    assert catalog.scopes.fetch(:global).fetch("after-new-window").fetch(:array)
    config = Tmux.configure { global.after_new_window[0] = "display-message hello" }
    assert_includes config.to_tmux, 'set-option -g after-new-window[0] "display-message hello"'
  end

  def test_catalog_parser_ignores_values_and_keeps_array_metadata
    parsed = Catalog.parse(<<~OUTPUT)
      prefix C-b
      user-keys
      status-format[0] "a value with spaces"
      status-format[1] "more"
      history-file ""
      @plugin "custom"
    OUTPUT

    assert_equal %w[prefix user-keys status-format history-file], parsed.keys
    assert_equal [false, true, true, false], parsed.values.map { |entry| entry.fetch(:array) }
  end

  def test_active_version_branches_validate_against_the_selected_target
    with_fake_target("3.2a", server: %w[old-setting]) do |target|
      config = Tmux.configure(tmux: target) do
        tmux_from("3.3") { server.new_setting = true }.else { server.old_setting = true }
        tmux_below("3.3") { server.old_setting = false }.else { server.new_setting = false }
      end
      assert_includes config.to_tmux, 'set-option -s new-setting on'
      assert_includes config.to_tmux, 'set-option -s old-setting on'
      assert_raises(Tmux::Error) do
        Tmux.configure(tmux: target) { tmux_from("3.2") { server.new_setting = true } }
      end
      assert_raises(Tmux::Error) do
        Tmux.configure(tmux: target) { tmux_below("3.2") { blank }.else { server.new_setting = true } }
      end
    end
  end

  def test_both_runtime_shell_branches_are_validated
    with_fake_target("3.2a", server: %w[old-setting]) do |target|
      assert_raises(Tmux::Error) do
        Tmux.configure(tmux: target) do
          if?(shell("true")) { server.old_setting = true }.else { server.new_setting = true }
        end
      end
    end
  end

  def test_imports_are_revalidated_for_the_destination_target
    with_fake_target("3.3a", server: %w[old-setting new-setting]) do |newer|
      component = Tmux.configure(tmux: newer) { server.new_setting = true }
      with_fake_target("3.2a", server: %w[old-setting]) do |older|
        assert_raises(Tmux::Error) { Tmux.configure(tmux: older) { append component } }
      end
    end
  end

  def test_target_context_is_inherited_and_restored_after_errors
    original = Target.current
    with_fake_target("3.3a", server: %w[new-setting]) do |target|
      captured = nil
      Tmux.configure(tmux: target) do
        captured = Tmux.configure { server.new_setting = true }
        append captured
      end
      assert_same target, captured.target
      assert_same original, Target.current
      assert_raises(RuntimeError) { Tmux.configure(tmux: target) { raise "stop" } }
      assert_same original, Target.current
    end
  end

  def test_no_static_fallback_is_used_when_the_target_is_missing
    error = assert_raises(Tmux::Error) { Tmux.configure(tmux: "/not/a/tmux") { global.prefix = "C-s" } }

    assert_match(/executable not found/, error.message)
  end

  def test_replacing_an_executable_invalidates_its_cached_version
    Dir.mktmpdir do |directory|
      executable = File.join(directory, "tmux")
      File.write(executable, "#!/bin/sh\nprintf 'tmux 3.2a\\n'\n")
      File.chmod(0o755, executable)
      old = Target.for_executable(executable)
      assert_equal "3.2a", old.version
      File.write(executable, "#!/bin/sh\nprintf 'tmux next-3.9\\n'\n")
      current = Target.for_executable(executable)

      refute_same old, current
      assert_equal "next-3.9", current.version
    end
  end

  def test_discovery_uses_only_isolated_sockets_and_always_cleans_up
    target = Target.new(Target.current.executable)
    calls = []
    success = Struct.new(:success?).new(true)
    failure = Struct.new(:success?).new(false)
    runner = lambda do |*args|
      calls << args
      next ["", "broken discovery", failure] if args.include?("show-options")

      ["", "", success]
    end
    target.stub(:version, "3.5a") do
      target.stub(:run, runner) do
        assert_raises(Tmux::Error) { target.catalog }
      end
    end

    assert_equal ["-S", calls.first.fetch(1), "-f", "/dev/null"], calls.first.take(4)
    assert calls.all? { |args| args.take(2) == calls.first.take(2) }
    assert_equal "kill-server", calls.last.last
    refute File.exist?(File.dirname(calls.first.fetch(1)))
  end

  def test_target_is_retained_when_rendering_after_path_changes
    config = Tmux.configure { global.prefix2 = "C-s" }
    saved = ENV["PATH"]
    ENV["PATH"] = "/not/a/path"

    assert_includes config.to_tmux, 'set-option -g prefix2 "C-s"'
  ensure
    ENV["PATH"] = saved
  end

  def test_real_available_versions_have_independent_catalogs
    binaries = Dir[File.expand_path("../tmp/tmux/*/bin/tmux", __dir__)]
    skip "additional tmux binaries are not built locally" if binaries.length < 2

    catalogs = binaries.map { |binary| Target.for_executable(binary).catalog }
    catalogs.each do |catalog|
      assert catalog.scopes.fetch(:global).key?("prefix2"), catalog.target.version
      assert catalog.scopes.fetch(:server).key?("escape-time"), catalog.target.version
    end
    older = catalogs.find { |catalog| catalog.target.version == "3.2a" }
    newer = catalogs.find { |catalog| catalog.target.version == "3.5a" }
    return unless older && newer

    refute older.scopes.fetch(:server).key?("extended-keys-format")
    assert newer.scopes.fetch(:server).key?("extended-keys-format")
    assert_raises(Tmux::Error) do
      Tmux.configure(tmux: older.target) { server.extended_keys_format = "csi-u" }
    end
    assert_includes Tmux.configure(tmux: newer.target) { server.extended_keys_format = "csi-u" }.to_tmux,
      'set-option -s extended-keys-format "csi-u"'
  end

  private

  def with_fake_target(version, server:)
    target = Target.new(Target.current.executable)
    scopes = {global: {}, window: {}, server: server.to_h { |name| [name, {array: false}] }}
    catalog = Catalog.new(target, scopes)
    target.stub(:catalog, catalog) do
      target.stub(:version, version) do
        target.stub(:canonical_name, nil) { yield target }
      end
    end
  end
end
