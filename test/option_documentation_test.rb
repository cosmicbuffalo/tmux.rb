require_relative "test_helper"

class OptionDocumentationTest < Minitest::Test
  def test_option_examples_match_their_native_tmux_comments
    readme = File.read(File.expand_path("../README.md", __dir__))
    ["Options by name", "Native names, custom options, and arrays",
      "Format-valued options", "Variable expansion"].each do |heading|
      section = readme.split("### #{heading}\n", 2).fetch(1).split("### ", 2).first
      code = section.match(/```ruby\n(.*?)\n```/m).captures.first
      native = code.lines.filter_map { |line| line[/# (set-option .*?)\s*$/, 1] }.join("\n") + "\n"

      refute_empty native.strip, heading
      # An actual ESC and its native octal spelling represent the same key.
      compiled = load_source(code).to_tmux.gsub("\e") { '\033' }
      assert_equal native, compiled, heading
    end
  end

  def test_key_binding_examples_match_their_native_tmux_comments
    readme = File.read(File.expand_path("../README.md", __dir__))
    section = readme.split("### Key bindings\n", 2).fetch(1).split("\n### ", 2).first
    blocks = section.scan(/```ruby\n(.*?)\n```/m).map(&:first)

    refute_empty blocks
    blocks.each do |code|
      native = code.lines.filter_map { |line| line[/# tmux: (.*?)\s*$/, 1] }.join("\n") + "\n"
      assert_equal native, load_source(code).to_tmux, code.lines.first
    end
  end
end
