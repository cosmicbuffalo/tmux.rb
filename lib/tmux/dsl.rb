# frozen_string_literal: true

module Tmux
  # Builds a Tmux::Format. The block runs on a FormatBuilder; give it one
  # parameter (`do |f| ... end`) to keep Ruby's normal scoping instead.
  def self.format(&block)
    builder = FormatBuilder.new
    Evaluation.run(builder, block)
    builder.build
  end

  # A reusable conditional format, with the same elsif? / else chain as if?
  # inside a format block.
  def self.if?(condition, &block)
    builder = FormatBuilder.new
    ConditionalFormat.new(builder, builder.if?(condition, &block))
  end

  # left/centre/right zones assembled into one aligned format (see ZoneBuilder).
  def self.pane_border(&block)
    builder = ZoneBuilder.new
    Evaluation.run(builder, block)
    builder.to_format
  end

  # Builds a Tmux::Config. The block runs on a ConfigBuilder; give it one
  # parameter (`do |c| ... end`) to keep Ruby's normal scoping instead.
  def self.configure(tmux: nil, &block)
    target = tmux ? Target.for_executable(tmux) : Target.current
    Target.with(target) do
      builder = ConfigBuilder.new(target: target)
      Evaluation.run(builder, block)
      builder.build
    end
  end

  # Coerces tmux format source: an Expression, or a String, Symbol, or Numeric
  # used verbatim. Ruby booleans and nil cannot represent runtime conditions.
  def self.expression(value)
    case value
    when Expression then value
    when String, Symbol, Numeric then raw(value)
    when true, false, nil
      raise Error, "expected a tmux expression, got #{value.inspect}; " \
        "use a tmux variable or expression comparison"
    else
      raise Error, "expected a tmux expression, String, Symbol, or Numeric, got #{value.class}"
    end
  end

  # An Expression from raw tmux format source, e.g. Tmux.raw("#{pane_id}").
  def self.raw(source) = Expression.new(source.to_s)

  # A deferred shell exit-status check for configuration conditionals.
  def self.shell(command, background: false)
    ShellCondition.new(command.to_s, background)
  end

  # A runtime conditional color/value, e.g.
  #   switch(prefix => colors.orange, copy_mode => colors.green, else: colors.tab)
  # compiles to #{?client_prefix,#ff8800,#{?pane_in_mode,#6a9955,#2d2d30}} — a
  # single expression usable anywhere a color is (fg:/bg:), so one mapping can
  # drive several attributes. The first case is the outermost condition; `else:`
  # is the fallback and is required. Values are tmux format source (colors,
  # expressions, or #{...} strings); stray "," and "}" are escaped, and so is
  # the "#" of an upper-case hex color, which tmux would otherwise read as a
  # variable like #F or #D once the branch is chosen.
  def self.switch(cases)
    default = cases.fetch(:else) { raise Error, "switch needs an else: value" }
    branches = cases.reject { |condition, _| condition.equal?(:else) }
    source = branches.reverse_each.reduce(switch_value(default)) do |rest, (condition, value)|
      "#{'#{'}?#{expression(condition).condition_source},#{switch_value(value)},#{rest}}"
    end
    raw(source)
  end

  def self.switch_value(value)
    source = Escape.structural(expression(value).source)
    source.gsub(/(?<!#)#(?=[A-F][0-9A-Fa-f]{5}(?![0-9A-Za-z]))/, "##")
  end
  private_class_method :switch_value

  def self.variable(name, shorthand: nil) = Variable.new(name, shorthand:)

  # Built-in tmux format variables, exposed as readers on the Tmux module so
  # any config can reach them directly (e.g. Tmux.pane_current_path). Keyed by
  # tmux's own variable name; the value is a shorthand (#S) where tmux has one.
  STANDARD_VARIABLES = {
    client_prefix: nil,
    pane_in_mode: nil,
    pane_input_off: nil,
    pane_mode: nil,
    pane_active: nil,
    pane_index: nil,
    pane_current_path: nil,
    pane_current_command: nil,
    pane_synchronized: nil,
    window_zoomed_flag: nil,
    window_index: "#I",
    window_name: "#W",
    session_name: "#S",
    host: "#H",
    host_short: "#h"
  }.freeze

  STANDARD_VARIABLES.each do |variable_name, shorthand|
    define_singleton_method(variable_name) { variable(variable_name, shorthand:) }
  end

  def self.user_option(name)
    option = normalize_user_option(name)
    Expression.new("#{'#{'}#{option}}", condition_source: option)
  end

  def self.normalize_user_option(name)
    "@#{name.to_s.delete_prefix('@')}"
  end
end
