# frozen_string_literal: true

module Tmux
  # Formats are compiled for the places tmux expands them with the time
  # (status line, window tabs, pane borders, titles, display-message): tmux
  # runs strftime over the top level and again over each conditional branch it
  # chooses, so a literal "%" in text needs doubling once per level.
  class FormatCompiler
    def compile(nodes, depth: 0)
      nodes.map { |node| compile_node(node, depth) }.join
    end

    private

    def compile_node(node, depth)
      branch = depth.positive?
      case node
      when Node::Text
        Escape.literal(node.value, branch:).gsub("%", "%" * (2**(depth + 1)))
      when Node::Strftime
        Escape.literal(node.value, branch:)
      when Node::Dynamic
        branch ? Escape.structural(node.expression.source) : node.expression.source
      when Node::Style
        "#[#{node.attributes.join(branch ? '#,' : ',')}]"
      when Node::ExpandOption
        "#{'#{'}E:#{node.name}}"
      when Node::Command
        "#(#{branch ? Escape.structural(node.command) : node.command})"
      when Node::Conditional
        condition = node.condition.condition_source
        on_true = compile(node.on_true, depth: depth + 1)
        on_false = compile(node.on_false, depth: depth + 1)
        "#{'#{'}?#{condition},#{on_true},#{on_false}}"
      else
        raise Error, "unknown format node: #{node.inspect}"
      end
    end
  end
  private_constant :FormatCompiler
end
