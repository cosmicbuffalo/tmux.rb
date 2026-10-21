# frozen_string_literal: true

module Tmux
  # tmux format escaping. "#" is tmux's escape character: "##", "#," and "#}"
  # stand for a literal "#", "," and "}". Inside a conditional branch (or an
  # operator argument) an unescaped "," or "}" ends that branch, so content
  # placed there needs all three escaped. Escapes do not compound with nesting:
  # tmux unescapes each branch once, when it expands the branch it chose.
  module Escape
    module_function

    # Literal text that tmux must not interpret at all.
    def literal(value, branch: false)
      escaped = value.to_s.gsub("#", "##")
      branch ? escaped.gsub(",", "#,").gsub("}", "#}") : escaped
    end

    # Format source (#{...}, #[...], #(...) written on purpose) placed inside
    # a branch: only the "," and "}" outside any #{...} would end the branch,
    # so only those are escaped. Existing "#x" escapes are left alone.
    def structural(source)
      result = +""
      each_top_level(source) do |token, top_level|
        # A lone trailing "#" would escape whatever follows the branch.
        result << (top_level && [",", "}", "#"].include?(token) ? "##{token}" : token)
      end
      result
    end

    # tmux matches parentheses inside #(...), so "$(cmd)" is fine, but an
    # unmatched ")" ends the command early (and "(" swallows the rest of the
    # format). tmux counts them everywhere, even inside #{...}, and neither can
    # be escaped.
    def unbalanced_parens?(source)
      depth = 0
      source.to_s.each_char do |char|
        depth += 1 if char == "("
        depth -= 1 if char == ")"
        return true if depth.negative?
      end
      !depth.zero?
    end

    # Yields each character (or two-character "#x" sequence) with whether it
    # sits outside every #{...}.
    def each_top_level(source)
      chars = source.to_s.chars
      depth = 0
      index = 0
      while index < chars.length
        if chars[index] == "#" && index + 1 < chars.length
          token = chars[index, 2].join
          yield token, depth.zero?
          depth += 1 if token == '#{'
          index += 2
        elsif chars[index] == "}" && depth.positive?
          depth -= 1
          yield "}", false
          index += 1
        else
          yield chars[index], depth.zero?
          index += 1
        end
      end
    end
  end
  private_constant :Escape
end
