require_relative "test_helper"
require "yaml"

# CI's tmux matrix and `rake test:tmux` should test the same versions.
class TmuxVersionsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_ci_and_rake_test_the_same_tmux_versions
    workflow = YAML.load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    rakefile = File.read(File.join(ROOT, "Rakefile"))[/^TMUX_VERSIONS = %w\[(.*?)\]/, 1].split

    assert_equal rakefile, workflow.dig("jobs", "tmux", "strategy", "matrix", "tmux")
  end
end
