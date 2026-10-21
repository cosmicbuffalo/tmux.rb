require_relative "test_helper"

# Screenshots render README examples (script/screenshots, which needs VHS).
# This checks, without rendering, that every scene points at a README
# example, every marked example has a scene, and each example loads into tmux
# the way the script loads it.
class ScreenshotScenesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    manifest = File.join(ROOT, "docs/screenshots/scenes.rb")
    @scenes = Module.new.module_eval(File.read(manifest), manifest)
    @examples = File.read(File.join(ROOT, "README.md"))
      .scan(/^<!-- example: ([\w-]+) -->\s*\n```ruby\n(.*?)^```$/m).to_h
  end

  def test_scenes_and_marked_examples_match
    assert_equal @examples.keys.sort, @scenes.map { |scene| scene.fetch(:example) }.uniq.sort
  end

  def test_every_scene_image_is_shown_in_the_readme
    readme = File.read(File.join(ROOT, "README.md"))
    @scenes.each do |scene|
      assert_includes readme, "(docs/images/#{scene.fetch(:name)}.png)"
      assert File.exist?(File.join(ROOT, "docs/images/#{scene.fetch(:name)}.png")), "missing #{scene[:name]}.png"
    end
  end

  def test_every_example_loads_into_tmux
    @scenes.uniq { |scene| scene.fetch(:example) }.each do |scene|
      Dir.mktmpdir do |directory|
        path = File.join(directory, "example.rb")
        File.write(path, @examples.fetch(scene[:example]))
        result = Tmux.load_file(path)
        if result.is_a?(Tmux::Format)
          options = Array(scene.fetch(:option))
          result = Tmux.configure do
            options.each do |name|
              scope = name.start_with?("window-") ? window : global
              scope[name] = result
            end
          end
        end
        with_tmux_server(result.to_tmux.gsub(/^run-shell .*$/, 'run-shell "true"')) do |tmux|
          assert tmux.call("show-options", "-g")
        end
      end
    end
  end
end
