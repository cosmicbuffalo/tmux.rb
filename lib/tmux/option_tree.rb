# frozen_string_literal: true

module Tmux
  def self.style_string(attributes)
    attributes.flat_map do |name, value|
      case name
      when :attrs then Array(value).map(&:to_s)
      when :fg, :bg
        raise Error, "style #{name}: needs a color, got nil" if value.nil?

        "#{name}=#{value}"
      else raise Error, "unknown style attribute: #{name}"
      end
    end.join(",")
  end

  class OptionNode
    def self.root(builder, scope)
      root = {children: {}, prefix: nil}
      builder.target.catalog.scopes.fetch(scope).each do |name, metadata|
        parts = name.split("-")
        paths = [parts]
        paths << parts.drop(1) if scope == :window && parts.first == "window"
        paths.each do |path|
          node = root
          offset = parts.length - path.length
          path.each_with_index do |key, index|
            node = (node[:children][key.to_sym] ||= {
              children: {}, prefix: parts.take(index + offset + 1).join("-")
            })
          end
          node.merge!(option: name, array: metadata[:array], style: style?(name))
        end
      end
      # Ergonomic aliases, not a list of valid options. Their availability is
      # still checked against the selected target, including in version gates.
      if scope == :window
        clock = root[:children][:clock] ||= {children: {}, prefix: "clock"}
        clock[:children][:colour] = {children: {}, prefix: "clock-mode-colour", option: "clock-mode-colour"}
        clock[:children][:hour_format] = {children: {}, prefix: "clock-mode-style", option: "clock-mode-style"}
      end
      new(builder, root, scope: scope)
    end

    def self.style?(name) = name.end_with?("-style") && name != "clock-mode-style"

    def initialize(builder, descriptor, scope:)
      @builder = builder
      @descriptor = descriptor
      @scope = scope
      # Kernel#display otherwise swallows namespaces such as display-panes.
      # Exact-name brackets remain available for collisions with this proxy's
      # own API (for example a future option literally named "set").
      inherited = Object.public_instance_methods - OptionNode.public_instance_methods(false)
      (descriptor[:children].keys & inherited).each do |key|
        define_singleton_method(key) do |*arguments|
          raise Error, "#{key} takes no arguments" unless arguments.empty?

          node_for(key.to_s)
        end
      end
    end

    def <<(value)
      write(value, append: true)
      self
    end

    def unset
      @builder.__send__(:remove_option, settable!("unset"), scope: @scope)
    end

    def set(*arguments, append: false, expand: true)
      return node_for("set") if arguments.empty? && known_child("set")
      raise Error, "set expects one value" unless arguments.length == 1

      write(arguments.first, append: append, expand: expand)
      self
    end

    # Exact tmux names also cover custom @options and names that collide with
    # Ruby methods. On a leaf, integer indexing selects a tmux array element.
    def [](key)
      name = if @descriptor[:prefix].nil?
        key.to_s.start_with?("@") ? key.to_s : key.to_s.tr("_", "-")
      else
        unless key.is_a?(Integer) && key >= 0
          raise Error, "option array index must be a nonnegative Integer"
        end
        "#{settable!('[]')}[#{key}]"
      end
      OptionNode.new(@builder, {children: {}, prefix: name, option: name, style: OptionNode.style?(name)}, scope: @scope)
    end

    def []=(key, value)
      self[key].__send__(:write, value)
      value
    end

    def respond_to_missing?(name, include_private = false)
      !!known_child(name.to_s.delete_suffix("=")) || super
    end

    def method_missing(name, *arguments)
      key = name.to_s
      if key.end_with?("=")
        raise Error, "#{key} expects one value" unless arguments.length == 1

        node_for(key.delete_suffix("=")).__send__(:write, arguments.first)
        return arguments.first
      end
      raise Error, "#{key} takes no arguments" unless arguments.empty?

      node_for(key)
    end

    private

    def known_child(key)
      return @descriptor[:children][key.to_sym] if @descriptor[:children].key?(key.to_sym)

      key.split("_").reduce(@descriptor) { |node, part| node && node[:children][part.to_sym] }
    end

    def node_for(key)
      descriptor = known_child(key)
      unless descriptor
        prefix = [@descriptor[:prefix], key.tr("_", "-")].compact.join("-")
        descriptor = {children: {}, prefix: prefix, style: OptionNode.style?(prefix)}
      end
      OptionNode.new(@builder, descriptor, scope: @scope)
    end

    def settable!(operation)
      return @descriptor[:option] if @descriptor[:option]
      return @descriptor[:prefix] if @descriptor[:children].empty? && @descriptor[:prefix]

      raise Error, "#{operation} needs a settable option, not a namespace"
    end

    def write(value, append: false, expand: true)
      name = settable!("assignment")
      value = Tmux.style_string(value) if @descriptor[:style] && value.is_a?(Hash)
      @builder.__send__(:write_option, name, value, scope: @scope, append: append, expand: expand)
    end
  end
  private_constant :OptionNode
end
