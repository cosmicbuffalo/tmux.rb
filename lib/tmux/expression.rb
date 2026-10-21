# frozen_string_literal: true

module Tmux
  class Expression
    attr_reader :source, :condition_source

    def initialize(source, condition_source: source)
      @source = source
      @condition_source = condition_source
    end

    # The tmux source, so expressions interpolate into text, binding commands,
    # and `append` source: "#{Tmux.session_name}" is "#{session_name}".
    def to_s = source

    # Logical negation. Written as #{?expr,0,1} because tmux's own #{!:...}
    # only exists from tmux 3.6.
    def ! = Expression.new("#{'#{'}?#{condition_source},0,1}")

    # String comparisons build tmux expressions, rather than Ruby booleans.
    def ==(other) = compare("==", other)
    def !=(other) = compare("!=", other)
    alias_method :eq, :==
    alias_method :not_eq, :!=

    # Structural equality for hashes and the library's format/style snapshots.
    def eql?(other)
      other.is_a?(Expression) && source.eql?(other.source) && condition_source.eql?(other.condition_source)
    end
    def hash = [Expression, source, condition_source].hash

    # Numeric comparisons (#{e|>:...}, tmux 3.2+); tmux's plain #{>:...}
    # compares strings, so 10 would sort before 9.
    def >(other) = compare("e|>", other)
    def <(other) = compare("e|<", other)
    def >=(other) = compare("e|>=", other)
    def <=(other) = compare("e|<=", other)

    # Regex match. A String pattern is literal regex text; the compiler escapes
    # the characters tmux itself would interpret.
    def matches(pattern)
      Expression.new("#{'#{'}m/r:#{argument(pattern)},#{source}}")
    end

    # Regex substitution. The delimiter is chosen automatically from characters
    # absent in the pattern and replacement, since tmux cannot escape it. A ":"
    # cannot appear in either: tmux ends the modifier there.
    def substitute(pattern, replacement)
      pattern = argument(pattern)
      replacement = argument(replacement)
      if pattern.include?(":") || replacement.include?(":")
        raise Error, "tmux's substitute modifier cannot contain \":\" (got #{pattern.inspect} -> #{replacement.inspect})"
      end
      delimiter = SUBSTITUTE_DELIMITERS.find do |candidate|
        !pattern.include?(candidate) && !replacement.include?(candidate)
      end
      raise Error, "substitute pattern and replacement use every delimiter (#{SUBSTITUTE_DELIMITERS.join})" unless delimiter

      d = delimiter
      Expression.new("#{'#{'}s#{d}#{pattern}#{d}#{replacement}#{d}:#{subject_source}}")
    end

    SUBSTITUTE_DELIMITERS = %w[| / ! @ ~ + = ^ &].freeze

    private

    # The text after a modifier's ":" — a bare variable name when possible,
    # otherwise the full nested format (which tmux expands).
    def subject_source
      source.match?(/\A#\{[^{}:]+\}\z/) ? source[2...-1] : source
    end

    def argument(value)
      return value.source if value.is_a?(Expression)
      return Escape.literal(value, branch: true) if value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric)

      raise Error, "expected an expression, String, Symbol, or Numeric operand, got #{value.inspect}"
    end

    def operation(operator, other)
      Expression.new("#{'#{'}#{operator}:#{source},#{Tmux.expression(other).source}}")
    end

    # Comparison operands that aren't expressions are literal values.
    def compare(operator, other)
      Expression.new("#{'#{'}#{operator}:#{source},#{argument(other)}}")
    end
  end

  # A single built-in tmux format variable, e.g. #{pane_current_path}. Behaves
  # as an Expression, so comparisons, #substitute and #matches all work on it.
  class Variable < Expression
    attr_reader :name, :shorthand

    def initialize(name, shorthand: nil)
      @name = name
      @shorthand = shorthand
      super(shorthand || "#{'#{'}#{name}}", condition_source: name.to_s)
    end

    # Always the long form, which is unambiguous wherever it is embedded and
    # which FormatBuilder#text recognizes as a dynamic part.
    def to_s = "#{'#{'}#{name}}"

    private

    def subject_source = name.to_s
  end
end
