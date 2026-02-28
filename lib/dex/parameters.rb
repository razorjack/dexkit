class Dex::Parameters < Dry::Struct
  SERIALIZED_COERCIONS = {
    Date => ->(v) { v.is_a?(String) ? Date.parse(v) : v },
    Time => ->(v) { v.is_a?(String) ? Time.parse(v) : v },
    DateTime => ->(v) { v.is_a?(String) ? DateTime.parse(v) : v },
    BigDecimal => ->(v) { v.is_a?(String) ? BigDecimal(v) : v },
    Symbol => ->(v) { v.is_a?(String) ? v.to_sym : v }
  }.freeze

  def as_json(options = nil)
    result = {}
    self.class.schema.each do |key|
      value = attributes[key.name]
      record_class = self.class._dex_extract_ref_class_from_type(key.type)

      result[key.name.to_s] = if record_class && value
        value.id
      else
        value.respond_to?(:as_json) ? value.as_json(options) : value
      end
    end
    result
  end

  class << self
    def _dex_coerce_serialized_hash(hash)
      result = {}
      schema.each do |key|
        name = key.name
        raw = hash.key?(name) ? hash[name] : hash[name.to_s]
        result[name] = _dex_coerce_value(key.type, raw)
      end
      result
    end

    def _dex_extract_ref_class_from_type(type)
      return type.meta[:dex_ref_class] if type.meta[:dex_ref_class]

      if type.respond_to?(:right)
        rc = type.right.meta[:dex_ref_class]
        return rc if rc
      end
      if type.respond_to?(:left)
        rc = type.left.meta[:dex_ref_class]
        return rc if rc
      end

      nil
    end

    def _dex_resolve_primitive(type)
      # Sum type (.optional) — recurse on right (non-nil) side
      if type.respond_to?(:right) && type.respond_to?(:left)
        return _dex_resolve_primitive(type.right)
      end

      return type.primitive if type.respond_to?(:primitive)

      # Default wrapper — unwrap via .type
      return _dex_resolve_primitive(type.type) if type.respond_to?(:type)

      nil
    rescue NoMethodError
      nil
    end

    private

    def _dex_coerce_value(type, value)
      return value unless value # nil/false pass through (VM-level check, no method call)
      return value if _dex_extract_ref_class_from_type(type)

      if type.respond_to?(:member)
        return value.map { |v| _dex_coerce_value(type.member, v) } if value.is_a?(Array)
        return value
      end

      primitive = _dex_resolve_primitive(type)
      coercion = SERIALIZED_COERCIONS[primitive]
      coercion ? coercion.call(value) : value
    end
  end

  private

  def _dex_extract_ref_class(type)
    self.class._dex_extract_ref_class_from_type(type)
  end
end
