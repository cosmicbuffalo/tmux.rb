require_relative "test_helper"

# The release workflow tags a version bump and uses its CHANGELOG section as
# the release notes, so a bump without that section should fail here, before
# it reaches main.
class ReleaseNotesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_the_current_version_has_release_notes
    notes, errors, status = Open3.capture3(File.join(ROOT, "script/release-notes"), Tmux::VERSION)

    assert status.success?, errors
    refute_empty notes.strip
  end

  def test_a_version_without_a_changelog_section_fails
    _notes, errors, status = Open3.capture3(File.join(ROOT, "script/release-notes"), "0.0.0")

    refute status.success?
    assert_includes errors, '"## 0.0.0 (...)"'
  end
end
