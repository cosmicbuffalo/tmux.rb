require "stringio"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/tmux/cli"

class CLITest < Minitest::Test
  def test_build_writes_configuration_atomically
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      output = File.join(directory, "tmux.conf")
      File.write(source, <<~RUBY)
        Tmux.configure do
          global.status.position = :top
        end
      RUBY

      status = Tmux::CLI.run(["build", source, "--output", output], stdout: StringIO.new, stderr: StringIO.new)

      assert_equal 0, status
      assert_equal "set-option -g status-position \"top\"\n", File.read(output)
    end
  end

  def test_check_uses_tmux_parse_only_validation
    require_tmux!

    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "Tmux.configure { global.status = true }\n")
      stdout = StringIO.new

      status = Tmux::CLI.run(["check", source], stdout:, stderr: StringIO.new)

      assert_equal 0, status
      assert_includes stdout.string, "tmux parsed the generated configuration (option names validated"
    end
  end

  def test_build_preserves_the_permissions_of_an_existing_output
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      output = File.join(directory, "tmux.conf")
      File.write(source, "Tmux.configure { global.mouse = true }\n")
      File.write(output, "old\n")
      File.chmod(0o640, output)

      status = Tmux::CLI.run(["build", source, "--output", output], stdout: StringIO.new, stderr: StringIO.new)

      assert_equal 0, status
      assert_equal 0o640, File.stat(output).mode & 0o777
      assert_equal ["config.rb", "tmux.conf"], Dir.children(directory).sort
    end
  end

  def test_unwritable_output_reports_a_one_line_error
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "Tmux.configure { global.mouse = true }\n")
      blocker = File.join(directory, "file")
      File.write(blocker, "")
      stderr = StringIO.new

      status = Tmux::CLI.run(["build", source, "--output", File.join(blocker, "tmux.conf")],
        stdout: StringIO.new, stderr:)

      assert_equal 1, status
      assert_match(/\Atmux.rb: .*file/, stderr.string)
      assert_equal 1, stderr.string.lines.size
    end
  end

  def test_configuration_errors_point_at_the_configuration_line
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "Tmux.configure do\n  global.mouse = true\n  undefined_helper\nend\n")
      stderr = StringIO.new

      status = Tmux::CLI.run(["build", source], stdout: StringIO.new, stderr:)

      assert_equal 1, status
      assert_match(/\Atmux.rb: #{Regexp.escape(source)}:3: undefined local variable or method .*\(NameError\)/, stderr.string)
    end
  end

  def test_every_example_builds
    Dir[File.expand_path("../examples/*.rb", __dir__)].each do |example|
      stdout = StringIO.new
      stderr = StringIO.new

      status = Tmux::CLI.run(["build", example], stdout:, stderr:)

      assert_equal 0, status, "#{File.basename(example)}: #{stderr.string}"
      refute_empty stdout.string
    end
  end

  def test_version_and_help_print_and_return_zero_without_exiting
    stdout = StringIO.new
    assert_equal 0, Tmux::CLI.run(["--version"], stdout:, stderr: StringIO.new)
    assert_equal "tmux.rb #{Tmux::VERSION}\n", stdout.string

    %w[--help help].each do |flag|
      stdout = StringIO.new
      assert_equal 0, Tmux::CLI.run([flag], stdout:, stderr: StringIO.new)
      assert_includes stdout.string, "tmux.rb build CONFIG.rb"
    end

    stdout = StringIO.new
    assert_equal 0, Tmux::CLI.run(["build", "--help"], stdout:, stderr: StringIO.new)
    assert_includes stdout.string, "usage: tmux.rb build CONFIG.rb [--output TMUX.conf]"
    assert_includes stdout.string, "--output PATH"
  end

  def test_unknown_commands_and_options_fail_with_usage
    stderr = StringIO.new
    assert_equal 2, Tmux::CLI.run(["bogus"], stdout: StringIO.new, stderr:)
    assert_includes stderr.string, "unknown command: bogus"

    stderr = StringIO.new
    assert_equal 1, Tmux::CLI.run(["build", "--nope", "x.rb"], stdout: StringIO.new, stderr:)
    assert_includes stderr.string, "invalid option: --nope"
  end

  def test_run_leaves_the_callers_arguments_untouched
    arguments = ["--version"].freeze
    Tmux::CLI.run(arguments, stdout: StringIO.new, stderr: StringIO.new)
    assert_equal ["--version"], arguments
  end

  def test_build_output_writes_through_a_symlink
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "Tmux.configure { global.mouse = true }\n")
      real = File.join(directory, "dotfiles", "tmux.conf")
      FileUtils.mkdir_p(File.dirname(real))
      File.write(real, "old\n")
      link = File.join(directory, ".tmux.conf")
      File.symlink(real, link)

      status = Tmux::CLI.run(["build", source, "--output", link], stdout: StringIO.new, stderr: StringIO.new)

      assert_equal 0, status
      assert File.symlink?(link), "the symlink was replaced"
      assert_equal "set-option -g mouse on\n", File.read(real)
    end
  end

  def test_load_errors_in_a_configuration_point_at_its_line
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "require \"tmux_rb_no_such_feature\"\nTmux.configure { }\n")
      stderr = StringIO.new

      status = Tmux::CLI.run(["build", source], stdout: StringIO.new, stderr:)

      assert_equal 1, status
      assert_match(/\Atmux.rb: #{Regexp.escape(source)}:1: cannot load such file .*\(LoadError\)/, stderr.string)
    end
  end

  def test_diff_reports_identical_generated_output
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      target = File.join(directory, "tmux.conf")
      File.write(source, "Tmux.configure { global.mouse = true }\n")
      File.write(target, "set-option -g mouse on\n")

      status = Tmux::CLI.run(["diff", source, target], stdout: StringIO.new, stderr: StringIO.new)

      assert_equal 0, status
    end
  end

  def test_load_renders_to_a_temporary_file_and_sources_it
    target = Tmux.const_get(:Target).current
    version = target.version
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "Tmux.configure { global[:@loaded_by_tmux_rb] = true }\n")
      invocation = nil
      rendered = nil
      success = Object.new
      def success.success? = true

      capture = lambda do |*command|
        next [version, "", success] if command.first == "display-message"

        invocation = command.take(2)
        rendered = File.read(command.fetch(1))
        ["", "", success]
      end

      status = target.stub(:run, capture) do
        Tmux::CLI.run(["load", source], stdout: StringIO.new, stderr: StringIO.new)
      end

      assert_equal 0, status
      assert_equal "source-file", invocation.first
      assert_equal "set-option -g @loaded_by_tmux_rb on\n", rendered
    end
  end

  def test_load_targets_an_explicit_server_instead_of_tmux_env
    target = Tmux.const_get(:Target).current
    version = target.version
    target.catalog
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, "Tmux.configure { global.mouse = true }\n")
      invocations = []
      success = Object.new
      def success.success? = true
      capture = lambda do |*command|
        next [version, "", success] if command.include?("display-message")

        invocations << command.take(3)
        ["", "", success]
      end

      target.stub(:run, capture) do
        Tmux::CLI.run(["load", "-S", "/tmp/outer.sock", source], stdout: StringIO.new, stderr: StringIO.new)
        Tmux::CLI.run(["load", "-L", "outer", source], stdout: StringIO.new, stderr: StringIO.new)
      end

      assert_equal [%w[-S /tmp/outer.sock source-file], %w[-L outer source-file]], invocations
    end
  end

  def test_load_refuses_a_different_server_version_before_sourcing_anything
    target = Tmux.const_get(:Target).current
    target.version
    target.catalog
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, 'Tmux.configure { global.prefix2 = "C-s" }')
      calls = []
      success = Struct.new(:success?).new(true)
      runner = ->(*args) { calls << args; ["other-version\n", "", success] }
      stderr = StringIO.new
      status = target.stub(:run, runner) do
        Tmux::CLI.run(["load", "-S", "/tmp/outer.sock", source], stdout: StringIO.new, stderr: stderr)
      end

      assert_equal 1, status
      assert_match(/destination server is tmux other-version/, stderr.string)
      assert_match(/--tmux PATH/, stderr.string)
      assert_equal [["-S", "/tmp/outer.sock", "display-message", "-p", '#{version}']], calls
    end
  end

  def test_cli_can_select_a_different_target_executable
    older = File.expand_path("../tmp/tmux/3.2a/bin/tmux", __dir__)
    skip "tmux 3.2a has not been built locally" unless File.executable?(older)

    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, 'Tmux.configure { server.extended_keys_format = "csi-u" }')
      stderr = StringIO.new
      status = Tmux::CLI.run(["build", "--tmux", older, source], stdout: StringIO.new, stderr: stderr)

      assert_equal 1, status
      assert_match(/unknown option "extended-keys-format" for tmux 3.2a/, stderr.string)
      File.write(source, 'Tmux.configure { global.prefix2 = "C-s" }')
      stdout = StringIO.new
      assert_equal 0, Tmux::CLI.run(["build", source, "--tmux", older], stdout: stdout, stderr: StringIO.new)
      assert_equal "set-option -g prefix2 \"C-s\"\n", stdout.string
    end
  end

  def test_configuration_is_evaluated_in_an_isolated_namespace
    Dir.mktmpdir do |directory|
      source = File.join(directory, "config.rb")
      File.write(source, <<~RUBY)
        TmuxCliIsolationSentinel = true
        Tmux.configure { global.mouse = true }
      RUBY

      status = Tmux::CLI.run(
        ["build", source],
        stdout: StringIO.new,
        stderr: StringIO.new
      )

      assert_equal 0, status
      refute Object.const_defined?(:TmuxCliIsolationSentinel, false)
    end
  end
end
