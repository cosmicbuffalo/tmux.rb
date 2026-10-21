# frozen_string_literal: true

module Tmux
  # How DSL blocks run. A block without parameters is instance_exec'd on the
  # builder, so builder methods can be called bare. A block that takes one
  # parameter (`do |c| ... end`) is called with the builder instead, keeping
  # Ruby's normal scoping for self, instance variables, and methods.
  module Evaluation
    def self.run(target, block)
      block.arity == 1 ? block.call(target) : target.instance_exec(&block)
    end

    private

    def evaluate(block) = Evaluation.run(self, block)
  end
  private_constant :Evaluation
end
