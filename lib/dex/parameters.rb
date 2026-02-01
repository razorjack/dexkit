class Dex::Parameters < Dry::Struct
  def as_json(options = nil)
    result = {}
    self.class.schema.each do |key|
      value = attributes[key.name]
      record_class = _dex_extract_record_class(key.type)

      result[key.name.to_s] = if record_class && value
        value.id
      else
        value.respond_to?(:as_json) ? value.as_json(options) : value
      end
    end
    result
  end

  private

  def _dex_extract_record_class(type)
    # Direct meta
    return type.meta[:dex_record_class] if type.meta[:dex_record_class]

    # Handle wrapped types (.optional creates Sum type with left/right)
    if type.respond_to?(:right)
      rc = type.right.meta[:dex_record_class]
      return rc if rc
    end
    if type.respond_to?(:left)
      rc = type.left.meta[:dex_record_class]
      return rc if rc
    end

    nil
  end
end
