# frozen_string_literal: true

require_relative "test_helper"

# Named format blocks that compile to one format and can be adjusted by name.
class SegmentsTest < Minitest::Test
  def bar
    Tmux.segments do
      segment(:path) { left_segment "path", bg: "colour236", fg: :white }
      segment(:host) { left_segment "host", bg: :blue, fg: :black }
    end
  end

  def test_compiles_like_the_same_blocks_written_as_one_format
    expected = Tmux.format do
      left_segment "path", bg: "colour236", fg: :white
      left_segment "host", bg: :blue, fg: :black
    end

    assert_equal expected, bar.to_format
  end

  def test_insert_before_and_after_a_named_segment
    segments = bar
      .insert(:clock, before: :host) { left_segment "clock", bg: "colour238", fg: :white }
      .insert(:cap, after: :host) { text "!" }
    expected = Tmux.format do
      left_segment "path", bg: "colour236", fg: :white
      left_segment "clock", bg: "colour238", fg: :white
      left_segment "host", bg: :blue, fg: :black
      text "!"
    end

    assert_equal %i[path clock host cap], segments.names
    assert_equal expected, segments.to_format
  end

  def test_replace_keeps_the_segments_place
    segments = bar.replace(:path) { left_segment "cwd", bg: "colour236", fg: :white }

    assert_equal %i[path host], segments.names
    assert_includes segments.to_tmux, "cwd"
    refute_includes segments.to_tmux, "path"
  end

  def test_remove_drops_segments
    assert_equal %i[host], bar.remove(:path).names
    assert_equal [], bar.remove(:path, :host).names
  end

  def test_a_block_with_a_parameter_receives_the_builder
    segments = Tmux.segments { |s| s.segment(:greeting) { |f| f.text "hi" } }

    assert_equal "hi", segments.to_tmux
  end

  def test_unknown_names_list_the_segments_there_are
    error = assert_raises(Tmux::Error) { bar.insert(:clock, before: :hots) { text "x" } }
    assert_equal "no segment :hots; segments are :path, :host", error.message
    assert_raises(Tmux::Error) { bar.replace(:nope) { text "x" } }
    assert_raises(Tmux::Error) { bar.remove(:nope) }
  end

  def test_names_must_be_unique_and_inserts_need_one_anchor
    assert_raises(Tmux::Error) { bar.segment(:host) { text "x" } }
    assert_raises(Tmux::Error) { bar.insert(:path, before: :host) { text "x" } }
    assert_raises(Tmux::Error) { bar.insert(:x, before: :host, after: :path) { text "x" } }
    assert_raises(Tmux::Error) { bar.insert(:x) { text "x" } }
  end

  def test_assigns_to_an_option_like_a_format
    segments = bar
    format = segments.to_format

    assert_equal Tmux.configure { global.status.right = format }.to_tmux,
      Tmux.configure { global.status.right = segments }.to_tmux
  end
end
