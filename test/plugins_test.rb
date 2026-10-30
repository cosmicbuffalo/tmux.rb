require_relative "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../lib/tmux/cli"

class PluginsTest < Minitest::Test
  ENV_NAMES = %w[TMUX_PLUGIN_MANAGER_PATH TMUX_RB_PLUGIN_PATH].freeze

  def setup
    @load_path = $LOAD_PATH.dup
    @env = ENV_NAMES.to_h { |name| [name, ENV[name]] }
    @root = Dir.mktmpdir("tmux_rb-plugins")
  end

  def teardown
    $LOAD_PATH.replace(@load_path)
    @env.each { |name, value| ENV[name] = value }
    FileUtils.rm_rf(@root)
  end

  # Creates files under @root/<dir> and returns that plugin's lib directory.
  def plugin(dir, files)
    files.each do |path, contents|
      file = File.join(@root, dir, path)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, contents)
    end
    File.join(@root, dir, "lib")
  end

  def test_tpm_directories_follow_tpm
    assert_equal ["/opt/plugins/"], Tmux::Plugins.tpm_directories("TMUX_PLUGIN_MANAGER_PATH" => "/opt/plugins/")
    assert_equal [File.join(Dir.home, ".tmux/plugins"), "/xdg/tmux/plugins"],
      Tmux::Plugins.tpm_directories("TMUX_PLUGIN_MANAGER_PATH" => "", "XDG_CONFIG_HOME" => "/xdg")
    assert_equal [File.join(Dir.home, ".tmux/plugins"), File.join(Dir.home, ".config/tmux/plugins")],
      Tmux::Plugins.tpm_directories({})
  end

  def test_search_path_puts_explicit_directories_before_tpm
    env = {"TMUX_RB_PLUGIN_PATH" => "/a:/b/:", "TMUX_PLUGIN_MANAGER_PATH" => "/tpm"}

    assert_equal ["/cli", "/a", "/b", "/tpm"], Tmux::Plugins.search_path(env, extra: ["/cli"])
  end

  def test_only_plugins_shipping_lib_named_after_themselves_are_found
    found = plugin("tpm/tmux-opted-in", "lib/tmux-opted-in.rb" => "")
    plugin("tpm/tmux-shell-helpers", "lib/helpers.sh" => "", "lib/json.rb" => "")
    plugin("tpm/tmux-no-lib", "tmux-no-lib.tmux" => "")

    assert_equal [found], Tmux::Plugins.load_paths({"TMUX_PLUGIN_MANAGER_PATH" => File.join(@root, "tpm")})
  end

  def test_a_plugin_checkout_can_be_named_directly_and_its_first_copy_wins
    tpm_copy = plugin("tpm/tmux-greeter", "lib/tmux-greeter.rb" => "")
    own_copy = plugin("src/tmux-greeter", "lib/tmux-greeter.rb" => "")
    other = plugin("tpm/tmux-other", "lib/tmux-other.rb" => "")
    env = {
      "TMUX_RB_PLUGIN_PATH" => File.join(@root, "src/tmux-greeter"),
      "TMUX_PLUGIN_MANAGER_PATH" => File.join(@root, "tpm")
    }

    assert_equal [own_copy, other], Tmux::Plugins.load_paths(env)
    refute_includes Tmux::Plugins.load_paths(env), tpm_copy
  end

  def test_plugin_load_paths_come_after_existing_ones_and_are_added_once
    found = plugin("tpm/tmux-opted-in", "lib/tmux-opted-in.rb" => "")
    env = {"TMUX_PLUGIN_MANAGER_PATH" => File.join(@root, "tpm")}

    2.times { Tmux::Plugins.add_to_load_path(env) }

    assert_equal found, $LOAD_PATH.last
    assert_equal 1, $LOAD_PATH.count(found)
  end

  def config_using(dir, name, constant)
    config = File.join(dir, "tmux.rb")
    File.write(config, %(require "#{name}"\nTmux.configure { use #{constant} }\n))
    config
  end

  def test_a_configuration_file_requires_a_plugin_by_name
    plugin("tpm/tmux-greeter", "lib/tmux-greeter.rb" => <<~RUBY)
      module TmuxGreeter
        def self.to_config = Tmux.configure { global[:@greeting] = "hello" }
      end
    RUBY
    ENV["TMUX_PLUGIN_MANAGER_PATH"] = File.join(@root, "tpm")

    Dir.mktmpdir do |dir|
      assert_equal %(set-option -g @greeting "hello"\n), Tmux.load_file(config_using(dir, "tmux-greeter", "TmuxGreeter")).to_tmux
    end
  end

  def test_the_cli_finds_a_plugin_on_its_plugin_path_without_tpm
    plugin("src/tmux-hello", "lib/tmux-hello.rb" => <<~RUBY)
      module TmuxHello
        def self.to_config = Tmux.configure { global[:@greeting] = "hi" }
      end
    RUBY
    ENV["TMUX_PLUGIN_MANAGER_PATH"] = File.join(@root, "no-tpm-here")

    Dir.mktmpdir do |dir|
      stdout, stderr = StringIO.new, StringIO.new
      status = Tmux::CLI.run(["build", config_using(dir, "tmux-hello", "TmuxHello"), "--plugin-path", File.join(@root, "src")], stdout:, stderr:)

      assert_equal 0, status, stderr.string
      assert_equal %(set-option -g @greeting "hi"\n), stdout.string
    end
  end

  def test_the_cli_says_where_it_looked_when_a_require_fails
    ENV["TMUX_PLUGIN_MANAGER_PATH"] = @root
    ENV["TMUX_RB_PLUGIN_PATH"] = nil
    Dir.mktmpdir do |dir|
      config = File.join(dir, "tmux.rb")
      File.write(config, %(require "tmux-missing"\nTmux.configure {}\n))
      stdout, stderr = StringIO.new, StringIO.new

      assert_equal 1, Tmux::CLI.run(["build", config, "--plugin-path", "/extra"], stdout:, stderr:)
      assert_match(/cannot load such file -- tmux-missing/, stderr.string)
      assert_includes stderr.string, "plugins are looked up in /extra, #{@root}"
      assert_includes stderr.string, "--plugin-path or TMUX_RB_PLUGIN_PATH"
    end
  end
end
