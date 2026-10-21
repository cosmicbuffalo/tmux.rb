# frozen_string_literal: true

module Tmux
  module Node
    Text = Data.define(:value)
    Strftime = Data.define(:value)
    Dynamic = Data.define(:expression)
    Style = Data.define(:attributes)
    ExpandOption = Data.define(:name)
    Command = Data.define(:command)
    Conditional = Data.define(:condition, :on_true, :on_false)
  end

  ConditionalStyleState = Data.define(:condition, :on_true, :on_false)
  CapturedFormat = Data.define(:nodes, :style_state)

  private_constant :ConditionalStyleState, :CapturedFormat

  # A compiled format string. #nodes is the read-only format AST.
  class Format
    attr_reader :nodes

    def initialize(nodes) = @nodes = nodes.freeze
    def to_tmux = FormatCompiler.new.compile(nodes)
    alias_method :to_s, :to_tmux
    def ==(other) = other.is_a?(Format) && nodes.eql?(other.nodes)
    alias_method :eql?, :==
    def hash = [Format, nodes].hash
  end

  # Returned by format and config conditionals so a conditional can
  # be written as `if?(cond) { … }.else { … }` (do/end blocks can't take
  # `else`).
  class Else
    def initialize(builder, index)
      @builder = builder
      @index = index
    end

    def else(&block)
      raise Error, ".else needs a block" unless block

      @builder.fill_else(@index, block)
      self
    end
  end

  # Format branches can also test further conditions before the final else.
  class FormatConditional < Else
    def elsif?(condition, &block)
      raise Error, ".elsif? needs a block" unless block

      @builder.fill_elsif(@index, condition, block)
      self
    end
  end

  class ConfigConditional < Else
    def elsif?(condition, background: false, &block)
      raise Error, ".elsif? needs a block" unless block

      @builder.fill_elsif(@index, condition, block, background:)
      self
    end
  end

  # Tmux.if? is both a reusable format and a chain that can add branches.
  # Each update replaces the frozen node snapshot without rerunning blocks.
  class ConditionalFormat < Format
    def initialize(builder, conditional)
      @builder = builder
      @conditional = conditional
      super(builder.build.nodes)
    end

    def elsif?(condition, &block)
      @conditional.elsif?(condition, &block)
      refresh
    end

    def else(&block)
      @conditional.else(&block)
      refresh
    end

    private

    def refresh
      @nodes = @builder.build.nodes
      self
    end
  end
  private_constant :Else, :FormatConditional, :ConfigConditional, :ConditionalFormat
end
