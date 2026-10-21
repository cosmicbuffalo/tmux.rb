# frozen_string_literal: true

require_relative "tmux/version"
require_relative "tmux/errors"
require_relative "tmux/escape"
require_relative "tmux/evaluation"
require_relative "tmux/expression"
require_relative "tmux/glyph"
require_relative "tmux/format"
require_relative "tmux/format_compiler"
require_relative "tmux/format_builder"
require_relative "tmux/zone_builder"
require_relative "tmux/config"
require_relative "tmux/config_compiler"
require_relative "tmux/command_builder"
require_relative "tmux/target"
require_relative "tmux/config_builder"
require_relative "tmux/option_tree"
require_relative "tmux/condition_compiler"
require_relative "tmux/dsl"

module Tmux
  # Evaluates a configuration file and returns the Tmux::Config or
  # Tmux::Format its final expression produces. The file runs inside a fresh
  # anonymous module, which keeps its constants and methods out of the global
  # namespace. Configuration files are trusted Ruby: the module is not a
  # sandbox. Logical operators in DSL conditions are captured before Ruby
  # evaluates them, so && / || build deferred tmux expressions.
  def self.load_file(path, tmux: nil)
    target = tmux ? Target.for_executable(tmux) : Target.current
    Target.with(target) { evaluate_file(path) }
  end

  def self.evaluate_file(path)
    absolute = File.expand_path(path)
    namespace = Module.new
    # Top-level `def` helpers become callable from the file's own code,
    # including blocks that take the builder as a parameter.
    namespace.extend(namespace)
    source = ConditionCompiler.rewrite(File.read(absolute), absolute)
    result = namespace.module_eval(source, absolute)
    return result if result.is_a?(Config) || result.is_a?(Format)

    raise Error, "#{path} must evaluate to a Tmux::Config or Tmux::Format"
  end
  private_class_method :evaluate_file
end
