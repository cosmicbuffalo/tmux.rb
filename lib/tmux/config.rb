# frozen_string_literal: true

module Tmux
  ShellCondition = Data.define(:command, :background)
  private_constant :ShellCondition

  module ConfigNode
    Blank = Data.define
    Command = Data.define(:text)
    SetOption = Data.define(:name, :value, :scope, :append, :expand)
    UnsetOption = Data.define(:name, :scope)
    IfShell = Data.define(:test, :success, :failure, :format, :background)
    # A %if/%else/%endif block, evaluated by tmux while it parses the file.
    Condition = Data.define(:condition, :body, :otherwise, :version, :direction)
  end

  # A compiled configuration. #nodes is the read-only configuration AST.
  class Config
    attr_reader :nodes, :target

    def initialize(nodes, target: Target.current)
      @nodes = nodes.freeze
      @target = target
    end

    def validate!
      OptionValidator.new(@target).validate(nodes)
      self
    end

    def to_tmux
      validate!
      ConfigCompiler.new.compile(nodes)
    end
    alias_method :to_s, :to_tmux
    def ==(other) = other.is_a?(Config) && nodes.eql?(other.nodes)
    alias_method :eql?, :==
    def hash = [self.class, nodes].hash
  end
end
