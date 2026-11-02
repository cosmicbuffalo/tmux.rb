# frozen_string_literal: true

module Tmux
  # An ordered list of named format blocks that compiles to one format, so a
  # status line built in one place can be adjusted in another: a machine's
  # config inserts, replaces, or removes segments by name before the format is
  # assigned. Blocks run in order on a single format builder when the format
  # is built, so powerline edges join neighbors as if written in one block.
  #
  #   right = Tmux.segments do
  #     segment(:path) { left_segment Tmux.pane_current_path, bg: "colour236", fg: :white }
  #     segment(:host) { left_segment Tmux.host, bg: :blue, fg: :black }
  #   end
  #   right.insert(:clock, before: :host) { left_segment "%H:%M", bg: "colour238", fg: :white }
  #   global.status.right = right
  class Segments
    def initialize(&block)
      @segments = []
      Evaluation.run(self, block) if block
    end

    # The segment names, in order.
    def names = @segments.map(&:first)

    # Adds a segment at the end.
    def segment(name, &block)
      raise Error, "segment #{name.inspect} needs a block" unless block
      raise Error, "segment #{name.inspect} is already defined" if names.include?(name)

      @segments << [name, block]
      self
    end

    # Adds a segment just before or after an existing one.
    def insert(name, before: nil, after: nil, &block)
      raise Error, "insert #{name.inspect}: give before: or after:, not both" if before && after
      raise Error, "insert #{name.inspect}: give before: or after:" unless before || after
      raise Error, "segment #{name.inspect} needs a block" unless block
      raise Error, "segment #{name.inspect} is already defined" if names.include?(name)

      index = position(before || after)
      @segments.insert(after ? index + 1 : index, [name, block])
      self
    end

    # Swaps an existing segment's block for a new one, keeping its place.
    def replace(name, &block)
      raise Error, "segment #{name.inspect} needs a block" unless block

      @segments[position(name)] = [name, block]
      self
    end

    def remove(*names_to_remove)
      names_to_remove.each { |name| @segments.delete_at(position(name)) }
      self
    end

    def to_format
      blocks = @segments.map(&:last)
      Tmux.format { blocks.each { |block| evaluate(block) } }
    end

    def to_tmux = to_format.to_tmux
    alias_method :to_s, :to_tmux

    private

    def position(name)
      names.index(name) or
        raise Error, "no segment #{name.inspect}; segments are #{names.map(&:inspect).join(', ')}"
    end
  end
end
