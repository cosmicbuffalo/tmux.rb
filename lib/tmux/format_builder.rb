# frozen_string_literal: true

module Tmux
  # The context of a Tmux.format block. Every DSL method returns the builder
  # (conditionals return a handle for `.else`), so calls can be chained.
  class FormatBuilder
    include Evaluation

    def initialize(style_state: nil, materialize_style_fallback: false)
      @nodes = []
      @style_state = style_state || {fg: nil, bg: nil, attrs: []}
      @materialize_style_fallback = materialize_style_fallback
      @conditional_states = {}
      # After a style block: [the style tmux has, the style to restore]. The
      # restore is emitted lazily (see #settle), so a following #style moves
      # straight to its own style instead of restoring first.
      @owed = nil
    end

    # Text, with expressions kept dynamic. Interpolate them into a string
    # (`text " #{Tmux.window_index} "`) or pass them as separate parts
    # (`text " ", Tmux.window_index, " "`); each balanced #{...} in a string
    # stays tmux format source. Everything else is literal: the compiler
    # escapes "#" and "%" (and "," and "}" inside branches). "#[" and "#("
    # are rejected, since styles and commands have their own methods; pass
    # `literal: true` to print a string exactly as written.
    def text(*parts, literal: false)
      parts.each do |part|
        next append(part) if part.is_a?(Expression) || part.is_a?(Format)

        string = part.to_s
        settle
        next @nodes << Node::Text.new(string) if literal

        if string.match?(/#[\[(]/)
          raise Error, "text #{string.inspect} contains a #[style] or #(command); use style or " \
            "command for those, or pass literal: true to print it as written"
        end
        interpolated_parts(string).each do |kind, chunk|
          @nodes << (kind == :format ? Node::Dynamic.new(Tmux.raw(chunk)) : Node::Text.new(chunk))
        end
      end
      self
    end

    # A strftime(3) date/time format such as "%a %H:%M", expanded by tmux each
    # time it renders. Unlike #text, its "%" codes are kept; "#", "," and "}"
    # are still escaped.
    def strftime(format)
      settle
      @nodes << Node::Strftime.new(format.to_s)
      self
    end

    # Appends tmux format source: an Expression, a String or Symbol of format
    # code used verbatim, or a Format whose content is spliced in. Unlike
    # #text, a String here is format code, not literal text.
    def append(content)
      settle
      if content.is_a?(Format)
        @nodes.concat(content.nodes)
      else
        @nodes << Node::Dynamic.new(Tmux.expression(content))
      end
      self
    end

    def reset_style
      @owed = nil
      @style_state = {fg: nil, bg: nil, attrs: []}
      @nodes << Node::Style.new(["default"])
      self
    end
    # A shell command run by tmux (#(...)). Its text is tmux format source, so
    # #{pane_id}-style codes expand before the shell sees it.
    def command(value)
      command = value.to_s
      if Escape.unbalanced_parens?(command)
        raise Error, "tmux cannot run #{command.inspect} in #(...): its parentheses are unbalanced; move it into a script"
      end
      settle
      @nodes << Node::Command.new(command)
      self
    end

    # Wrap the body produced by the block with surrounding text. Pass prefix and
    # suffix directly (`wrap("[", "]")`), or pass a proc that receives a
    # placeholder (`wrap ->(x) { " (#{x}) " }`). The active style is restored
    # before the suffix, including styles selected by #switch_style.
    def wrap(prefix_or_template, suffix = nil, &block)
      if prefix_or_template.respond_to?(:call)
        raise Error, "wrap cannot combine a template proc with a suffix" if suffix

        marker = "\u0000"
        prefix, suffix = prefix_or_template.call(marker).split(marker, 2)
      else
        prefix = prefix_or_template
        suffix ||= ""
      end
      settle
      entry_style = @style_state
      text(prefix) unless prefix.to_s.empty?
      body_style = fallback_style(entry_style)
      unless body_style.eql?(entry_style)
        restyle(body_style, force: true)
        @style_state = body_style
      end
      previous_fallback_mode = @materialize_style_fallback
      @materialize_style_fallback = true
      evaluate(block) if block
      @materialize_style_fallback = previous_fallback_mode
      restyle(entry_style, force: true)
      @style_state = entry_style
      text(suffix) unless suffix.to_s.empty?
      self
    end

    # Select a complete style at tmux render time. Unlike using Tmux.switch as
    # one fg/bg value, this emits a conditional around whole #[...] style nodes,
    # which mirrors hand-written tmux formats and can be restored by #wrap.
    def switch_style(cases)
      settle
      default = cases.fetch(:else) { raise Error, "switch_style needs an else: style" }
      branches = cases.reject { |condition, _| condition.equal?(:else) }
      base = @style_state
      nodes, state = style_branch(default, base)

      branches.reverse_each do |condition, attributes|
        on_true, true_state = style_branch(attributes, base)
        expression = Tmux.expression(condition)
        nodes = [Node::Conditional.new(expression, on_true, nodes)]
        state = conditional_style_state(expression, true_state, state)
      end

      @nodes.concat(nodes)
      @style_state = state
      self
    end

    # A FLAG is a self-contained chunk of the bar: given colors + content it
    # emits both edges, the fg/bg swap, and the attr reset. left_ is for the
    # right-aligned bar (left-pointing edges); right_ for the left-aligned bar.
    # `content` may be the first positional arg or the `content:` keyword (a
    # String or an Expression like Tmux.pane_mode); a block body is emitted
    # verbatim instead. `p:` is the number of space pad chars on each side of the
    # content (default 1; 0 for none). `over:` is the color behind the pointed
    # edge: the previous background for left_ helpers, :default for right_.
    # `notch_over:` can give a flag's notch a different surrounding color;
    # by default it uses the same color as `over:`.
    # `attrs:` styles the content only, never the edges (terminals draw bold
    # text in a named color's bright variant, which would recolor a bold
    # edge), and is reset after the chunk so it never leaks. `glyph:` overrides the edge shape. Pass `close: false` for
    # an open flag, or use left_segment/right_segment.
    def left_flag(content_arg = nil, bg:, fg:, content: nil, p: 1, attrs: nil, over: nil, notch_over: nil, glyph: :triangle, close: true, &block)
      content = content_arg unless content_arg.nil?
      flag(Glyph.resolve(glyph, side: :left), leading: true, bg:, fg:, content:, p:, attrs:, over:, notch_over:, close:, &block)
    end

    def right_flag(content_arg = nil, bg:, fg:, content: nil, p: 1, attrs: nil, over: nil, notch_over: nil, glyph: :triangle, close: true, &block)
      content = content_arg unless content_arg.nil?
      flag(Glyph.resolve(glyph, side: :right), leading: false, bg:, fg:, content:, p:, attrs:, over:, notch_over:, close:, &block)
    end

    # A SEGMENT is a chain piece: one shared edge, no closing glyph — it butts
    # against its neighbor. Same options as a flag minus close.
    def left_segment(content_arg = nil, bg:, fg:, content: nil, p: 1, attrs: nil, over: nil, glyph: :triangle, &block)
      content = content_arg unless content_arg.nil?
      flag(Glyph.resolve(glyph, side: :left), leading: true, bg:, fg:, content:, p:, attrs:, over:, close: false, &block)
    end

    def right_segment(content_arg = nil, bg:, fg:, content: nil, p: 1, attrs: nil, over: nil, glyph: :triangle, &block)
      content = content_arg unless content_arg.nil?
      flag(Glyph.resolve(glyph, side: :right), leading: false, bg:, fg:, content:, p:, attrs:, over:, close: false, &block)
    end

    # A CHIP is a floating double-ended badge: a left glyph in, the content, and
    # a right glyph out, both edges in the chip's `bg` over the surrounding color
    # (`over:`, default :default). `content`/`fg`/`bg`/`p:` work like a segment;
    # a block body is emitted verbatim. Style is reset afterward, so the chip is
    # fully self-contained. With two thin edges, the text uses the outline
    # color and the body shares the edges' surrounding background.
    def chip(content_arg = nil, bg:, fg:, content: nil, p: 1, over: :default, left: :triangle, right: :triangle, &block)
      content = content_arg unless content_arg.nil?
      left_glyph = Glyph.resolve(left, side: :left)
      right_glyph = Glyph.resolve(right, side: :right)
      thin = Glyph.thin?(left_glyph) && Glyph.thin?(right_glyph)
      style(fg: bg, bg: over)
      text left_glyph
      style(fg: thin ? bg : fg, bg: thin ? over : bg)
      emit_body(content, p, block)
      style(fg: bg, bg: over)
      text right_glyph
      reset_style
      self
    end

    # Emit a style. `attrs`/`fg`/`bg` set the style for what follows. With a
    # block, the style applies only to the block's body, padded with `p`
    # spaces each side (default 0), and the style from before the block is
    # restored after it: `style(fg: x, p: 1) { append y }` is style, " ", body,
    # " ", then the previous style again.
    def style(attributes = nil, p: 0, **keywords, &block)
      properties = style_properties(attributes)
      properties.merge!(keywords)
      values, operations = style_operations(properties)
      raise Error, "style requires at least one attribute" if values.empty? && !block

      entry_style = @style_state
      if values.empty?
        settle
      elsif @owed
        # Straight from the previous block's style to this one: what was
        # written, plus whatever undoes the block and this doesn't override.
        target = apply_style(@style_state, operations)
        @nodes.concat(transition_nodes(@owed.first, target, written: values))
        @owed = nil
        @style_state = target
      else
        @nodes << Node::Style.new(values)
        @style_state = apply_style(@style_state, operations)
      end
      return self unless block

      pad = " " * p
      text(pad) unless pad.empty?
      evaluate(block)
      text(pad) unless pad.empty?
      settle
      @owed = [@style_state, entry_style]
      @style_state = entry_style
      self
    end

    def expand_option(name)
      settle
      @nodes << Node::ExpandOption.new(Tmux.normalize_user_option(name))
      self
    end

    def if?(condition, &block) = conditional(condition, on_true: block)
    def switch(cases) = Tmux.switch(cases)

    def conditional(condition, on_true: nil, on_false: nil)
      settle
      expression = Tmux.expression(condition)
      entry_style = @style_state
      success = capture(on_true, style_state: entry_style)
      failure = capture(on_false, style_state: entry_style)
      index = @nodes.size
      @nodes << Node::Conditional.new(expression, success.nodes, failure.nodes)
      context = @conditional_states[index] = {
        entry_style:, branches: [[expression, on_true, success]], failure:,
        has_else: !on_false.nil?
      }
      rebuild_conditional(index, context)
      FormatConditional.new(self, index)
    end

    def fill_elsif(index, condition, block)
      context = open_conditional(index, ".elsif?")
      expression = Tmux.expression(condition)
      branch = capture(block, style_state: context.fetch(:entry_style))
      context.fetch(:branches) << [expression, block, branch]
      rebuild_conditional(index, context)
    end

    # Fills the final fallback of the conditional just appended.
    def fill_else(index, block)
      context = open_conditional(index, ".else")
      context[:failure] = capture(block, style_state: context.fetch(:entry_style))
      context[:has_else] = true
      rebuild_conditional(index, context)
    end


    def build = Format.new(@nodes.dup)

    private

    def open_conditional(index, method)
      context = @conditional_states[index]
      unless @nodes[index].is_a?(Node::Conditional) && context
        raise Error, "#{method} must directly follow the if? it belongs to"
      end
      raise Error, "this conditional already has an else branch" if context[:has_else]

      context
    end

    # Captured blocks run once. Rebuild only their nested false branches and
    # style snapshots as elsif? / else branches are added to the chain.
    def rebuild_conditional(index, context)
      entry_style = context.fetch(:entry_style)
      failure = context.fetch(:failure)
      nodes = failure.nodes
      state = failure.style_state
      style_only = style_nodes_only?(nodes)
      has_fallback = context.fetch(:has_else)

      context.fetch(:branches).reverse_each do |condition, block, branch|
        style_only &&= style_nodes_only?(branch.nodes)
        success_nodes = branch.nodes
        if style_only && @materialize_style_fallback
          success_nodes = inherited_style_nodes(entry_style) unless block
          nodes = inherited_style_nodes(entry_style) unless has_fallback
        end
        nodes = [Node::Conditional.new(condition, success_nodes, nodes)]
        state = if style_only
          conditional_style_state(condition, branch.style_state, state)
        else
          entry_style
        end
        has_fallback = true
      end

      @nodes[index] = nodes.first
      @style_state = state
    end

    # Emits a restore owed by a style block, before content that should be
    # drawn in the restored style.
    def settle
      return unless @owed

      from, to = @owed
      @owed = nil
      @nodes.concat(transition_nodes(from, to))
    end

    # Style nodes that change tmux's current style `from` into `to`, starting
    # from the style values the configuration `written` itself.
    def transition_nodes(from, to, written: [])
      plain = [from, to].none? { |state| state.is_a?(ConditionalStyleState) }
      dropped = plain ? from[:attrs] - to[:attrs] : []
      unless plain && dropped.none? { |attr| attr.include?("=") }
        # Attributes such as align=right can't be switched off by name.
        return [Node::Style.new(["default"]), *style_state_nodes(to)]
      end

      values = written.dup
      %i[fg bg].each do |name|
        next if from[name].eql?(to[name]) || values.any? { |value| value.start_with?("#{name}=") }

        values << "#{name}=#{to[name] || 'default'}"
      end
      values.concat(to[:attrs] - from[:attrs] - values)
      values.concat(dropped.map { |attr| "no#{attr}" } - values)
      values.empty? ? [] : [Node::Style.new(values)]
    end

    public


    private

    # Splits a string into literal text and balanced #{...} format chunks.
    def interpolated_parts(string)
      parts = []
      literal = +""
      index = 0
      while index < string.length
        if string[index, 2] == "\#{"
          closing = matching_brace(string, index + 1)
          raise Error, "text #{string.inspect} has an unclosed \#{" unless closing

          parts << [:text, literal] unless literal.empty?
          parts << [:format, string[index..closing]]
          literal = +""
          index = closing + 1
        else
          literal << string[index]
          index += 1
        end
      end
      parts << [:text, literal] unless literal.empty?
      parts
    end

    def matching_brace(string, open_index)
      depth = 0
      (open_index...string.length).each do |index|
        depth += 1 if string[index] == "{"
        depth -= 1 if string[index] == "}"
        return index if depth.zero?
      end
      nil
    end

    # style(fg: :red), style(:bold), style([:bold, :italics]), or a Hash.
    def style_properties(attributes)
      case attributes
      when nil then {}
      when Hash then attributes.dup
      when Symbol, String, Array then {attrs: attributes}
      else
        raise Error, "style expects a Hash of fg:/bg:/attrs: or attribute names, got #{attributes.inspect}"
      end
    end

    def style_color(value) = value.is_a?(Expression) ? value.source : value.to_s

    def style_operations(properties)
      values = []
      operations = []
      properties.each do |name, value|
        if name.equal?(:attrs)
          Array(value).map(&:to_s).each do |attribute|
            values << attribute
            operations << [:attr, attribute]
          end
        elsif %i[fg bg].include?(name)
          raise Error, "style #{name}: needs a color, got nil" if value.nil?

          values << "#{name}=#{style_color(value)}"
          operations << [name, value]
        else
          raise Error, "unknown style attribute: #{name}"
        end
      end
      [values, operations]
    end

    def apply_style(state, operations)
      if state.is_a?(ConditionalStyleState)
        conditional_style_state(
          state.condition,
          apply_style(state.on_true, operations),
          apply_style(state.on_false, operations)
        )
      else
        result = state.merge(attrs: state[:attrs].dup)
        operations.each do |name, value|
          if name == :attr
            if value == "default" || value == "none"
              result = {fg: nil, bg: nil, attrs: []}
            elsif value.start_with?("no") && value.length > 2
              result[:attrs].delete(value.delete_prefix("no"))
            else
              result[:attrs] << value unless result[:attrs].include?(value)
            end
          else
            result[name] = value
          end
        end
        result
      end
    end

    def conditional_style_state(condition, on_true, on_false)
      on_true.eql?(on_false) ? on_true : ConditionalStyleState.new(condition, on_true, on_false)
    end

    def fallback_style(state)
      state.is_a?(ConditionalStyleState) ? fallback_style(state.on_false) : state
    end

    def style_branch(attributes, base)
      properties = attributes.respond_to?(:to_h) ? attributes.to_h : {}
      values, operations = style_operations(properties)
      nodes = values.empty? ? [] : [Node::Style.new(values)]
      [nodes, apply_style(base, operations)]
    end

    # Re-emit a captured style snapshot. Conditional snapshots remain
    # conditional, allowing a wrapper suffix to inherit the same runtime style
    # as its prefix.
    def restyle(state, force: false)
      settle
      @nodes.concat(style_state_nodes(state, force:))
    end

    def style_state_nodes(state, force: false)
      if state.is_a?(ConditionalStyleState)
        [Node::Conditional.new(
          state.condition,
          style_state_nodes(state.on_true, force: true),
          style_state_nodes(state.on_false, force: true)
        )]
      else
        values = []
        values << "fg=#{state[:fg]}" if state[:fg]
        values << "bg=#{state[:bg]}" if state[:bg]
        values.concat(state[:attrs])
        values = ["default"] if values.empty? && force
        values.empty? ? [] : [Node::Style.new(values)]
      end
    end

    # Runs a branch block on this same builder with a fresh node buffer, so
    # helper methods and instance variables stay visible in nested blocks.
    def capture(block, style_state: @style_state)
      return CapturedFormat.new([], style_state) unless block

      saved = [@nodes, @style_state, @conditional_states, @owed]
      @nodes = []
      @style_state = style_state
      @conditional_states = {}
      @owed = nil
      evaluate(block)
      settle
      CapturedFormat.new(@nodes, @style_state)
    ensure
      @nodes, @style_state, @conditional_states, @owed = saved if saved
    end

    def style_nodes_only?(nodes)
      nodes.all? do |node|
        node.is_a?(Node::Style) ||
          (node.is_a?(Node::Conditional) &&
            style_nodes_only?(node.on_true) && style_nodes_only?(node.on_false))
      end
    end

    def inherited_style_nodes(state)
      default_style?(state) ? [] : style_state_nodes(state, force: true)
    end

    def default_style?(state)
      !state.is_a?(ConditionalStyleState) &&
        state[:fg].nil? && state[:bg].nil? && state[:attrs].empty?
    end

    def flag(edge_char, leading:, bg:, fg:, content:, p:, attrs:, over:, close:, notch_over: nil, &block)
      # A leading edge sits over the previous chip's bg, which the style tracker
      # already knows — so `over:` defaults to it (falling back to :default).
      over = (leading ? style_value(@style_state, :bg) : nil) || :default if over.nil?
      notch_over = over if notch_over.nil?
      body_style = attrs ? {attrs: attrs} : {}
      # A flag's notch is cut into the end opposite its point: after the body
      # of a left flag, before the body of a right flag.
      notch(edge_char, bg:, over: notch_over) if close && !leading
      if leading
        style(fg: bg, bg: over)
        text edge_char
      end
      style({fg: fg, bg: bg}.merge(body_style))
      emit_body(content, p, block)
      unless leading
        style(fg: bg, bg: over)
        text edge_char
      end
      # Attrs never leak past the chunk.
      reset_attrs(attrs)
      notch(edge_char, bg:, over: notch_over) if close && leading
      self
    end

    # The notch is cut in the color behind the flag, so the next block starts
    # from that color. tmux can't name the terminal's own background as a
    # foreground color, so the glyph is drawn reversed: the cell takes the
    # flag's color and the glyph takes `over`, even when `over` is :default.
    def notch(edge_char, bg:, over:)
      style(fg: bg, bg: over, attrs: :reverse)
      text edge_char
      style(attrs: :noreverse)
    end

    def reset_attrs(attrs)
      off = Array(attrs).map { |attr| "no#{attr}" }
      style(attrs: off) unless off.empty?
    end

    def style_value(state, name)
      return state[name] unless state.is_a?(ConditionalStyleState)

      on_true = style_value(state.on_true, name) || :default
      on_false = style_value(state.on_false, name) || :default
      return on_true if on_true.eql?(on_false)

      Tmux.switch(state.condition => on_true, else: on_false)
    end

    # Emit a flag/segment body: a block verbatim, otherwise `content` padded with
    # `count` spaces each side. A String is literal text, an Expression stays
    # dynamic, and an Array mixes both like #text.
    def emit_body(content, count, block)
      return evaluate(block) if block
      return if content.nil?

      pad = " " * count
      text(pad) unless pad.empty?
      text(*Array(content))
      text(pad) unless pad.empty?
    end
  end
end
