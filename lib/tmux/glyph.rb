# frozen_string_literal: true

module Tmux
  # Named edge/separator glyphs (Powerline private-use codepoints), so configs
  # write `:left_triangle` instead of an opaque "\u{e0b2}". Referenced by name in
  # the flag helpers, or reachable directly as Tmux::Glyph::LEFT_TRIANGLE.
  module Glyph
    CHARS = {
      right_triangle: "\u{e0b0}", right_thin: "\u{e0b1}",
      left_triangle: "\u{e0b2}",  left_thin: "\u{e0b3}",
      right_round: "\u{e0b4}",    right_round_thin: "\u{e0b5}",
      left_round: "\u{e0b6}",     left_round_thin: "\u{e0b7}",
      lower_left_triangle: "\u{e0b8}", upper_left_triangle: "\u{e0bc}",
      lower_right_triangle: "\u{e0ba}", upper_right_triangle: "\u{e0be}"
    }.freeze
    CHARS.each { |name, char| const_set(name.to_s.upcase, char) }

    # Shapes describe an edge independently of its position. A slant keeps
    # its slope on both sides, using complementary filled triangles.
    SHAPES = {
      triangle: {left: :left_triangle, right: :right_triangle},
      thin: {left: :left_thin, right: :right_thin},
      round: {left: :left_round, right: :right_round},
      round_thin: {left: :left_round_thin, right: :right_round_thin},
      rslant: {left: :lower_right_triangle, right: :upper_left_triangle},
      lslant: {left: :upper_right_triangle, right: :lower_left_triangle}
    }.transform_values(&:freeze).freeze
    private_constant :SHAPES

    THIN_GLYPHS = CHARS.values_at(:left_thin, :right_thin, :left_round_thin, :right_round_thin).freeze
    private_constant :THIN_GLYPHS

    def self.[](name) = CHARS.fetch(name) { raise Error, "unknown glyph: #{name}" }
    def self.thin?(glyph) = THIN_GLYPHS.include?(glyph)

    def self.resolve(value, side: nil)
      return value.to_s unless value.is_a?(Symbol)

      if (shape = SHAPES[value])
        value = shape.fetch(side) { raise Error, "glyph #{value.inspect} needs a side (:left or :right)" }
      end
      self[value]
    end
  end
end
