require_relative "test_helper"

# The README's "At a glance" section claims its hand-written tmux.conf and its
# tmux.rb version load identically. Source each into its own tmux server and
# compare what tmux ends up with.
class ReadmeGlanceTest < Minitest::Test
  README = File.expand_path("../README.md", __dir__)

  def test_glance_examples_load_identically
    blocks = File.read(README).scan(/^<!-- glance: (\w+) -->\s*\n```\w+\n(.*?)^```$/m).to_h
    native = blocks.fetch("tmux")
    generated = load_source(blocks.fetch("ruby")).to_tmux

    assert_equal tmux_state(native), tmux_state(generated)
  end

  private

  def tmux_state(config)
    with_tmux_server(config) do |tmux|
      [["show-options", "-g"], ["show-options", "-gw"], ["list-keys"]].to_h do |arguments|
        [arguments.join(" "), tmux.call(*arguments)]
      end
    end
  end
end
