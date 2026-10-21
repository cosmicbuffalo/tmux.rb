require_relative "test_helper"

# examples/author_config.rb is the complete real-world example. Its generated
# output is pinned (UPDATE_FIXTURES=1 rewrites the fixture after an intended
# change), it must load into a real tmux server, and its window tabs are
# rendered by tmux across every attention state.
class AuthorConfigTest < Minitest::Test
  REPOSITORY = File.expand_path("..", __dir__)
  EXAMPLE_PATH = File.join(REPOSITORY, "examples/author_config.rb")
  FIXTURE_PATH = File.join(REPOSITORY, "test/fixtures/author_config.conf")

  # Commands that reach outside tmux, replaced so the isolated server never
  # installs plugins or talks to pmux.
  EXTERNAL_INTEGRATIONS = {
    "~/.tmux/plugins/tpm/tpm" => "true",
    "~/.config/pmux/outer-tmux.conf" => "/dev/null"
  }.freeze

  INACTIVE = "#[fg=#2d2d30,bg=#5eaceb] 0 #[fg=#5eaceb,bg=#2d2d30]"
  ACTIVE = "#[fg=#000000,bg=#ff8800] 0 #[fg=#ffffff,bg=#4e4e4e]"
  INACTIVE_NAME = "#[fg=#5eaceb,bg=#2d2d30]"
  ACTIVE_NAME = "#[fg=#ffffff,bg=#4e4e4e]"
  SEGMENT = "#[fg=black,bg=yellow] ! "

  def setup
    @config = Tmux.load_file(EXAMPLE_PATH)
  end

  def test_generated_output_matches_the_fixture
    # The reload binding and "~/" substitution embed build-time paths.
    output = @config.to_tmux.gsub(REPOSITORY, "<repository>").gsub(Dir.home, "<home>")
    File.write(FIXTURE_PATH, output) if ENV["UPDATE_FIXTURES"]

    assert_equal File.read(FIXTURE_PATH), output,
      "generated config changed; rerun with UPDATE_FIXTURES=1 if intended"
  end

  def test_reload_binding_recompiles_this_file
    assert_includes @config.to_tmux,
      %(bind-key "r" run-shell "tmux.rb load -S \\"\#{socket_path}\\" #{EXAMPLE_PATH}" \\; display-message "Configuration reloaded")
  end

  def test_external_integrations_are_wired_up
    EXTERNAL_INTEGRATIONS.each_key do |integration|
      assert @config.to_tmux.include?(integration), "author config no longer references #{integration}"
    end
  end

  def test_loads_into_tmux_without_errors
    with_server { |tmux| assert_equal "C-s", tmux.call("show-options", "-gv", "prefix").chomp }
  end

  def test_window_tabs_render_every_attention_state
    with_server do |tmux|
      window = ->(*arguments) { tmux.call("set-option", "-w", "-t", "verify:editor", *arguments) }
      tabs = -> { %w[window-status-format window-status-current-format].map { |option| tab(tmux, option) } }

      assert_equal ["#{INACTIVE} #{INACTIVE_NAME}editor #[default]",
        "#{ACTIVE} #{ACTIVE_NAME}editor #[default]"], tabs.call

      tmux.call("split-window", "-t", "verify:editor", "sleep 3600")
      tmux.call("resize-pane", "-Z", "-t", "verify:editor")
      assert_equal ["#{INACTIVE} #{INACTIVE_NAME}#[fg=colour44](editor) #[default]",
        "#{ACTIVE} #{ACTIVE_NAME}#[fg=colour44](editor) #[default]"], tabs.call
      tmux.call("resize-pane", "-Z", "-t", "verify:editor")

      window.call("synchronize-panes", "on")
      assert_equal ["#{INACTIVE} #{INACTIVE_NAME}editor #[fg=brightred](sync) #[default]",
        "#{ACTIVE} #{ACTIVE_NAME}editor #[fg=brightred](sync) #[default]"], tabs.call
      window.call("synchronize-panes", "off")

      # A steady ai-attn segment hands back to the name colors after itself.
      window.call("@ai_attn_window_state", "done")
      window.call("@ai_attn_window_segment", SEGMENT)
      steady = ["#{INACTIVE}#{SEGMENT}#{INACTIVE_NAME}editor #[default]",
        "#{ACTIVE}#{SEGMENT}#{ACTIVE_NAME}editor #[default]"]
      assert_equal steady, tabs.call

      # While a flash is lit the segment's colors run through the name.
      window.call("@ai_attn_window_flash", "1")
      tmux.call("set-option", "-g", "@ai_attn_flash_phase", "1")
      assert_equal ["#{INACTIVE}#{SEGMENT}editor #[default]", "#{ACTIVE}#{SEGMENT}editor #[default]"], tabs.call
      tmux.call("set-option", "-g", "@ai_attn_flash_phase", "0")
      assert_equal steady, tabs.call

      # A pmux flash strips the segment's own style and paints it cyan.
      window.call("@pmux_flash_window", "on")
      cyan = "#[fg=colour235,bg=cyan]"
      assert_equal ["#{INACTIVE}#{cyan} ! #{cyan}editor #[default]",
        "#{ACTIVE}#{cyan} ! #{cyan}editor #[default]"], tabs.call
    end
  end

  private

  def tab(tmux, option)
    render(tmux, "\#{E:#{option}}")
  end

  def with_server(&block)
    contents = EXTERNAL_INTEGRATIONS.reduce(@config.to_tmux) do |result, (external, harmless)|
      result.gsub(external, harmless)
    end
    with_tmux_server(contents, &block)
  end
end
