require "fileutils"
require "open3"
require "securerandom"
require "tempfile"
require "tmpdir"
require_relative "test_helper"
require_relative "style_equivalence"

class PopularConfigsEquivalenceTest < Minitest::Test
  include StyleEquivalence

  ROOT = File.expand_path("..", __dir__)
  EXAMPLES = File.join(ROOT, "examples", "popular_configs")
  # Startup snapshots clear the environment, PATH included, so resolve tmux
  # up front; a bare "tmux" misses Homebrew's /opt/homebrew/bin on macOS.
  TMUX = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
    .map { |dir| File.join(dir, "tmux") }
    .find { |path| File.executable?(path) } || "tmux"

  CASES = {
    tony: {native: ".tmux.conf"},
    thoughtbot: {native: ".tmux.conf"},
    alrra: {native: ".tmux.conf"},
    anishathalye: {native: ".tmux.conf"},
    skwp: {native: ".tmux.conf"},
    maximum_awesome: {
      native: ".tmux.conf",
      files: {
        "original.tmux.conf" => ".tmux.conf",
        "original.tmux.conf.local" => ".tmux.conf.local"
      }
    },
    dikiaap: {native: ".tmux.conf"},
    xero: {native: ".config/tmux/tmux.conf"},
    nicknisi: {
      native: ".config/tmux/tmux.conf",
      files: {
        "original.tmux.conf" => ".config/tmux/tmux.conf",
        "original.theme.tmux" => ".config/tmux/theme/theme.tmux"
      }
    },
    oh_my_tmux: {
      native: ".tmux.conf",
      full_engine: true,
      files: {
        "original.tmux.conf" => ".tmux.conf",
        "original.tmux.conf.local" => ".tmux.conf.local"
      }
    }
  }.freeze

  CASES.each do |name, paths|
    define_method("test_#{name}_port_reproduces_effective_tmux_state") do
      assert_port_equivalence(name, paths)
    end
  end

  def test_anishathalye_status_formats_use_the_format_ast
    path = File.join(EXAMPLES, "anishathalye", "tmux.rb")
    options = load_port(path).nodes.grep(Tmux::ConfigNode::SetOption).to_h do |node|
      [node.name, node.value]
    end

    assert_instance_of Tmux::Format, options.fetch("status-left")
    assert_instance_of Tmux::Format, options.fetch("status-right")
  end

  def test_dikiaap_theme_formats_use_the_format_ast
    path = File.join(EXAMPLES, "dikiaap", "tmux.rb")
    config = load_port(path)
    options = config.nodes.grep(Tmux::ConfigNode::SetOption).to_h do |node|
      [node.name, node.value]
    end

    %w[status-left status-right window-status-format window-status-current-format].each do |name|
      assert_instance_of Tmux::Format, options.fetch(name)
    end

    generated = config.to_tmux
    assert_includes generated,
      'bind-key "r" run-shell "tmux.rb load -S \"#{socket_path}\" \\\\~/.config/tmux/tmux.rb" \\; display-message "tmux reloaded"'
  end

  def test_tony_status_formats_use_the_format_ast
    path = File.join(EXAMPLES, "tony", "tmux.rb")
    options = load_port(path).nodes.grep(Tmux::ConfigNode::SetOption).to_h do |node|
      [node.name, node.value]
    end

    assert_instance_of Tmux::Format, options.fetch("status-left")
    assert_instance_of Tmux::Format, options.fetch("status-right")
  end

  def setup
    require_tmux!
  end

  private

  def assert_port_equivalence(name, paths)
    Dir.mktmpdir("tmux-rb-popular-#{name}") do |directory|
      home = File.join(directory, "home")
      FileUtils.mkdir_p(home)
      example = File.join(EXAMPLES, name.to_s)
      files = paths.fetch(:files, {"original.tmux.conf" => paths.fetch(:native)})
      files.each do |source, destination|
        target = File.join(home, destination)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(example, source), target)
      end

      native_path = File.join(home, paths.fetch(:native))
      native = File.read(native_path)
      unless paths[:full_engine]
        native = sanitized(native, home:)
        File.write(native_path, native)
      end
      generated = load_port(File.join(example, "tmux.rb")).to_tmux

      if paths[:full_engine]
        refute_includes generated, "cut -c3-"
        refute_includes generated, "original.tmux.conf"
        refute_match(/^source-file\s+["']?~\/\.tmux\.conf/, generated)
      end

      environment = paths[:full_engine] ? isolated_environment(home) : nil
      expected = snapshot(
        native, label: "#{name}-native", startup: paths[:full_engine], environment:
      )
      actual = snapshot(
        sanitized(generated, home:), label: "#{name}-ruby",
        startup: paths[:full_engine], environment:
      )
      expected = normalized_snapshot(expected, name, home)
      actual = normalized_snapshot(actual, name, home)

      expected.each do |category, value|
        observed = actual.fetch(category)
        missing = value - observed
        extra = observed - value
        assert missing.empty? && extra.empty?, <<~MESSAGE
          #{name} port changed #{category.to_s.tr('_', ' ')}
          missing: #{missing.inspect}
          extra: #{extra.inspect}
        MESSAGE
      end
    end
  end

  def load_port(path)
    result = Tmux.load_file(path)
    assert_instance_of Tmux::Config, result, "#{path} must return a Tmux::Config"
    result
  end

  # Top-level integrations are represented in key bindings and options but are
  # never allowed to launch plugin managers or host-specific scripts in tests.
  def sanitized(contents, home:)
    contents
      .gsub("$HOME", home)
      .gsub(%r{(?<=[\s"'])~/}, "#{home}/")
      .gsub(/^(?:run|run-shell)\s+.*$/, 'run-shell "true"')
  end

  def snapshot(contents, label:, startup: false, environment: nil)
    socket = File.join(
      Dir.tmpdir,
      "tmux-rb-#{label}-#{Process.pid}-#{SecureRandom.hex(4)}.sock"
    )

    Tempfile.create([label, ".conf"]) do |file|
      file.write(contents)
      file.flush

      if startup
        run_tmux(
          socket, "-f", file.path, "new-session", "-d", "-s", "verify", "sleep 60",
          environment:
        )
      else
        run_tmux(
          socket, "-f", "/dev/null", "new-session", "-d", "-s", "verify", "sleep 60"
        )
        run_tmux(socket, "source-file", file.path)
      end

      {
        global_options: lines(run_tmux(socket, "show-options", "-g")),
        global_window_options: lines(run_tmux(socket, "show-options", "-gw")),
        server_options: lines(run_tmux(socket, "show-options", "-s")),
        key_tables: lines(run_tmux(socket, "list-keys")),
        global_hooks: lines(run_tmux(socket, "show-hooks", "-g")),
        global_environment: environment_lines(
          run_tmux(socket, "show-environment", "-g"), socket
        )
      }
    ensure
      run_tmux(socket, "kill-server", allow_failure: true) if socket
      FileUtils.rm_f(socket) if socket
    end
  end

  def lines(output)
    output.lines(chomp: true).map { |line| normalize_styles(line) }.sort
  end

  def environment_lines(output, socket)
    lines(output).map do |line|
      line == "TMUX_SOCKET=#{socket}" ? "TMUX_SOCKET=<runtime socket>" : line
    end
  end

  def isolated_environment(home)
    {
      "HOME" => home,
      # The tmux under test first: the upstream engine calls `tmux` itself
      # and adapts to the version it reports.
      "PATH" => [File.dirname(File.expand_path(TMUX)), "/usr/bin", "/bin"].uniq.join(":"),
      "SHELL" => "/bin/sh",
      "USER" => "tmux-rb",
      "TERM" => "xterm-256color",
      "COLORTERM" => "",
      "XDG_SESSION_TYPE" => ""
    }
  end

  def normalized_snapshot(snapshot, name, home)
    if %i[dikiaap tony].include?(name)
      return snapshot.transform_values do |entries|
        entries.map { |line| normalize_ruby_reload(line, name) }.sort
      end
    end
    return snapshot unless name == :oh_my_tmux

    snapshot.transform_values do |entries|
      entries.filter_map { |line| normalize_oh_my_tmux(line, home) }.sort
    end
  end

  def normalize_ruby_reload(line, name)
    return "bind-key -T prefix r <#{name}-reload>" if line.match?(/\Abind-key.*-T prefix\s+r\s/)

    line
  end

  def normalize_oh_my_tmux(line, home)
    return if line.match?(/\A@(uptime|battery)_/)
    return if line.start_with?("@__apply_plugins ")
    return if line.match?(/\A(?:TMUX_CONF(?:_LOCAL)?|TMUX_PROGRAM|TMUX_PLUGIN_MANAGER_PATH)=/)
    return if line == "TMUX_SOCKET=<runtime socket>"

    if line.match?(/\Abind-key.*-T prefix\s+e\s/)
      return "bind-key -T prefix e <oh-my-tmux-edit>"
    end
    if line.match?(/\Abind-key.*-T prefix\s+r\s/)
      return "bind-key -T prefix r <oh-my-tmux-reload>"
    end
    if line.match?(/\Abind-key.*-T prefix\s+y\s/) && line.include?("save-buffer")
      return "bind-key -T prefix y <oh-my-tmux-copy-to-clipboard>"
    end

    line
      .gsub(home, "<HOME>")
      .gsub(%r{#\(cut -c3- '[^']+\.tmux\.conf' \| sh -s _username ([^)]*)\)}, '#(<oh-my-tmux username \1>)')
      .gsub(%r{#\([^)]*runtime\.rb username ([^)]*)\)}, '#(<oh-my-tmux username \1>)')
      .gsub(%r{#\(cut -c3- '[^']+\.tmux\.conf' \| sh -s _hostname ([^)]*)\)}, '#(<oh-my-tmux hostname \1>)')
      .gsub(%r{#\([^)]*runtime\.rb hostname ([^)]*)\)}, '#(<oh-my-tmux hostname \1>)')
      .gsub(%r{cut -c3- '[^']+' \| sh -s _maximize_pane}, "<oh-my-tmux maximize>")
      .gsub(%r{/\S*ruby\S*\s+\S*runtime\.rb maximize}, "<oh-my-tmux maximize>")
      .gsub(%r{cut -c3- '[^']+' \| sh -s _fpp}, "<oh-my-tmux fpp>")
      .gsub(%r{/\S*ruby\S*\s+\S*runtime\.rb fpp}, "<oh-my-tmux fpp>")
      .gsub(/#\{(\?)?battery_/, '#{\1@battery_')
      .gsub(/"?\$TMUX_PROGRAM"? \$\{TMUX_SOCKET:\+-S "\$TMUX_SOCKET"\}/, "tmux")
  end

  def run_tmux(socket, *arguments, allow_failure: false, environment: nil)
    if environment
      stdout, stderr, status = Open3.capture3(
        environment, TMUX, "-S", socket, *arguments, unsetenv_others: true
      )
    else
      stdout, stderr, status = Open3.capture3(TMUX, "-S", socket, *arguments)
    end
    return stdout if status.success? || allow_failure

    raise "tmux failed for #{socket}: #{stderr}#{stdout}"
  end
end
