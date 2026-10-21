module StyleEquivalence
  # Canonicalize attribute order within #[...] style blocks whose attributes
  # commute, so #[fg=x,bg=y] and #[bg=y,fg=x] (identical once rendered)
  # compare equal. Blocks where order matters are left exactly as written:
  # "default"/"none" reset what precedes them, "no..." toggles undo an earlier
  # attribute, and a repeated key overrides an earlier one. Handles top-level
  # "," separators and the conditional-escaped "#," form.
  def normalize_styles(text)
    text.gsub(/#\[[^\]]*\]/) do |block|
      parts = block[2...-1].split(/#?,/)
      commutes?(parts) ? "#[#{parts.sort.join(',')}]" : block
    end
  end

  private

  def commutes?(parts)
    keys = parts.map { |part| part.split("=", 2).first }
    keys.uniq.size == keys.size &&
      parts.none? { |part| %w[default none].include?(part) || part.start_with?("no") }
  end
end
