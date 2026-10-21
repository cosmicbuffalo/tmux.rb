# frozen_string_literal: true

module Tmux
  # Collects left/centre/right zone blocks and assembles them, in that order
  # regardless of definition order, into one aligned format — for a status line
  # or pane border. Each zone's body is an ordinary format block.
  class ZoneBuilder
    def left(&block) = @left = block
    def center(&block) = @center = block
    def centre(&block) = @center = block
    def right(&block) = @right = block

    def to_format
      left, center, right = @left, @center, @right
      Tmux.format do
        evaluate(left) if left
        if center
          reset_style
          style attrs: "align=centre"
          evaluate(center)
        end
        if right
          reset_style
          style attrs: "align=right"
          evaluate(right)
        end
      end
    end
  end
  private_constant :ZoneBuilder
end
