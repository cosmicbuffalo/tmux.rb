# frozen_string_literal: true

require "prism"

module Tmux
  # Capture Ruby syntax before && / || can discard symbolic operands. This is
  # source translation, not an override of Ruby's truthiness or short circuiting.
  class ConditionCompiler
    EXPRESSION_NODES = %i[
      and_node or_node call_node arguments_node parentheses_node statements_node
      local_variable_read_node instance_variable_read_node constant_read_node
      constant_path_node self_node string_node interpolated_string_node
      embedded_statements_node symbol_node interpolated_symbol_node integer_node
      float_node true_node false_node nil_node array_node hash_node
      keyword_hash_node assoc_node
    ].freeze

    def self.rewrite(source, path)
      compiler = new(source, path)
      edits = compiler.nodes.flat_map do |node|
        compiler.conditions(node).filter_map do |argument|
          next unless compiler.logical?(argument)

          compiler.validate!(argument)
          [argument.location, compiler.render(argument)]
        end
      end
      compiler.replace(nil, edits)
    end

    attr_reader :root

    def initialize(source, path)
      @source = source
      @path = path
      result = Prism.parse(source, filepath: path)
      unless result.errors.empty?
        error = result.errors.first
        raise Error, "#{path}:#{error.location.start_line}: #{error.message}"
      end
      @root = result.value
    end

    def nodes(node = root)
      [node] + node.compact_child_nodes.flat_map { |child| nodes(child) }
    end

    def logical?(node)
      return false if %i[block_node lambda_node].include?(node.type)

      %i[and_node or_node].include?(node.type) || node.compact_child_nodes.any? { |child| logical?(child) }
    end

    def conditions(node)
      return [] unless node.type == :call_node

      argument = node.arguments&.arguments&.first
      return [] unless argument
      return [argument] if %i[if? elsif?].include?(node.name)
      return [] unless %i[switch switch_style].include?(node.name)
      return [] unless %i[hash_node keyword_hash_node].include?(argument.type)

      argument.elements.filter_map { |entry| entry.key if entry.type == :assoc_node }
    end

    def validate!(node)
      unless node && EXPRESSION_NODES.include?(node.type)
        fail_at(node, "condition needs a single expression; assignments and control flow are not supported")
      end
      if node.type == :statements_node && node.body.length != 1
        fail_at(node, "condition needs a single expression")
      end
      if node.type == :call_node && (node.block || node.safe_navigation?)
        fail_at(node, "blocks and safe navigation are not supported inside a condition")
      end
      if %i[and_node or_node].include?(node.type) && !%w[&& ||].include?(node.operator_loc.slice)
        fail_at(node, "use && / || rather than and / or in a condition")
      end
      if node.compact_child_nodes.any? { |child| child.location.end_offset > node.location.end_offset }
        fail_at(node, "heredocs are not supported inside a captured condition; use a string or local variable")
      end
      node.compact_child_nodes.each { |child| validate!(child) }
    end

    def render(node)
      if %i[and_node or_node].include?(node.type)
        operator = node.type == :and_node ? "&&" : "||"
        edits = [
          [node.left.location, "::Tmux.expression((#{render(node.left)})).__send__(:operation, #{operator.inspect}, ("],
          [node.operator_loc, ""],
          [node.right.location, "#{render(node.right)}))"]
        ]
        return replace(node.location, edits)
      end

      edits = node.compact_child_nodes.map { |child| [child.location, render(child)] }
      replace(node.location, edits)
    end

    # Prism offsets count bytes, not characters. Keep comments, whitespace and
    # newlines intact so Unicode and error backtraces retain their original lines.
    # An outer edit already contains the rendering of any nested edits.
    def replace(location, edits)
      start_offset = location&.start_offset || 0
      end_offset = location&.end_offset || @source.bytesize
      result = @source.byteslice(start_offset...end_offset).b
      boundary = start_offset
      selected = edits.sort_by { |range, _| [range.start_offset, -range.length] }.select do |range, _|
        next false if range.start_offset < boundary

        boundary = range.end_offset
        true
      end
      selected.reverse_each do |range, replacement|
        result[range.start_offset - start_offset, range.length] = replacement.b
      end
      result.force_encoding(@source.encoding)
    end

    private

    def fail_at(node, message)
      raise Error, "#{@path}:#{node&.location&.start_line || 1}: #{message}"
    end
  end
  private_constant :ConditionCompiler
end
