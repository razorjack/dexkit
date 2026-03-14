# frozen_string_literal: true

module Dex
  module Tool
    QUERY_TOOL_OPTIONS = %i[scope serialize limit only_filters except_filters only_sorts].freeze

    module_function

    def from(klass, **opts)
      _require_ruby_llm!

      if klass < Dex::Query
        _validate_query_tool_options!(klass, opts)
        _build_query_tool(klass, **opts)
      elsif klass < Dex::Operation
        _reject_unknown_options!(klass, opts)
        _build_tool(klass)
      else
        raise ArgumentError, "expected a Dex::Operation or Dex::Query subclass, got #{klass}"
      end
    end

    def all
      _require_ruby_llm!
      Operation.registry.sort_by(&:name).map { |klass| _build_tool(klass) }
    end

    def from_namespace(namespace)
      _require_ruby_llm!
      prefix = "#{namespace}::"
      Operation.registry
        .select { |op| op.name&.start_with?(prefix) }
        .sort_by(&:name)
        .map { |klass| _build_tool(klass) }
    end

    def explain_tool
      _require_ruby_llm!
      _build_explain_tool
    end

    def _require_ruby_llm!
      require "ruby_llm"
    rescue LoadError
      raise LoadError,
        "Dex::Tool requires the ruby-llm gem. Add `gem 'ruby_llm'` to your Gemfile."
    end

    # --- Operation tools ---

    def _build_tool(operation_class)
      op = operation_class
      schema = op.contract.to_json_schema
      tool_description = _tool_description(op)

      Class.new(RubyLLM::Tool) do
        define_method(:name) { "dex_#{op.name.gsub("::", "_").downcase}" }
        define_method(:description) { tool_description }
        define_method(:params_schema) { schema }

        define_method(:execute) do |**params|
          coerced = params.transform_keys(&:to_sym)
          result = op.new(**coerced).safe.call
          case result
          when Dex::Operation::Ok
            value = result.value
            value.respond_to?(:as_json) ? value.as_json : value
          when Dex::Operation::Err
            { error: result.code, message: result.message, details: result.details }
          end
        end
      end.new
    end

    def _tool_description(op)
      parts = []
      desc = op.description
      parts << desc if desc
      parts << op.name unless desc

      guards = op.contract.guards
      if guards.any?
        messages = guards.map { |g| g[:message] || g[:name].to_s }
        parts << "Preconditions: #{messages.join("; ")}."
      end

      errors = op.contract.errors
      parts << "Errors: #{errors.join(", ")}." if errors.any?

      parts.join("\n")
    end

    def _reject_unknown_options!(_klass, opts)
      return if opts.empty?

      raise ArgumentError, "#{opts.keys.first}: is not a valid option for Operation tools"
    end

    # --- Query tools ---

    def _validate_query_tool_options!(klass, opts)
      unknown = opts.keys - QUERY_TOOL_OPTIONS
      unless unknown.empty?
        raise ArgumentError, "unknown option#{"s" if unknown.size > 1}: #{unknown.map { |k| "#{k}:" }.join(", ")}"
      end

      label = klass.name || klass.inspect

      unless opts.key?(:scope)
        raise ArgumentError, "#{label} is a Dex::Query. Query tools require scope: and serialize:.\n" \
          "Example: Dex::Tool.from(#{label},\n" \
          "  scope: -> { Current.user.orders },\n" \
          "  serialize: ->(record) { record.as_json(only: [:id, :name]) })"
      end

      unless opts.key?(:serialize)
        raise ArgumentError, "#{label} is a Dex::Query. Query tools require serialize:.\n" \
          "Example: Dex::Tool.from(#{label},\n" \
          "  scope: -> { Current.user.orders },\n" \
          "  serialize: ->(record) { record.as_json(only: [:id, :name]) })"
      end

      unless klass._scope_block
        raise ArgumentError, "#{label} has no scope block. Define scope { ... } in the query class."
      end

      unless opts[:scope].respond_to?(:call)
        raise ArgumentError, "scope: must respond to call (lambda or proc)"
      end

      unless opts[:serialize].respond_to?(:call)
        raise ArgumentError, "serialize: must respond to call (lambda or proc)"
      end

      if opts.key?(:limit)
        unless opts[:limit].is_a?(Integer) && opts[:limit] > 0
          raise ArgumentError, "limit: must be a positive integer"
        end
      end

      if opts.key?(:only_filters) && opts.key?(:except_filters)
        raise ArgumentError, "only_filters: and except_filters: are mutually exclusive"
      end

      declared_filters = klass.filters
      if opts.key?(:only_filters)
        context_mapped = klass.context_mappings.keys.to_set
        opts[:only_filters].each do |f|
          f_sym = f.to_sym
          unless declared_filters.include?(f_sym)
            raise ArgumentError, "unknown filter :#{f}. Declared: #{declared_filters.inspect}"
          end

          if context_mapped.include?(f_sym)
            raise ArgumentError, "filter :#{f} is context-mapped and automatically excluded from " \
              "tool schema. Remove it from only_filters:"
          end

          prop = klass.literal_properties.find { |p| p.name == f_sym }
          if prop && _ref_type?(prop.type)
            raise ArgumentError, "filter :#{f} backs a _Ref prop and is automatically excluded from " \
              "tool schema. Remove it from only_filters:"
          end
        end
      end

      if opts.key?(:except_filters)
        opts[:except_filters].each do |f|
          unless declared_filters.include?(f.to_sym)
            raise ArgumentError, "unknown filter :#{f} in except_filters. Declared: #{declared_filters.inspect}"
          end
        end
      end

      declared_sorts = klass.sorts
      if opts.key?(:only_sorts)
        opts[:only_sorts].each do |s|
          unless declared_sorts.include?(s.to_sym)
            raise ArgumentError, "unknown sort :#{s}. Declared: #{declared_sorts.inspect}"
          end
        end

        default_sort = klass._sort_default
        if default_sort
          bare = default_sort.delete_prefix("-").to_sym
          unless opts[:only_sorts].map(&:to_sym).include?(bare)
            raise ArgumentError, "query default sort #{default_sort} is not in only_sorts. " \
              "Include it or change the query's default"
          end
        end
      end

      if klass.respond_to?(:literal_properties)
        klass.literal_properties.each do |prop|
          if %i[limit offset].include?(prop.name)
            raise ArgumentError, "#{label} declares prop :#{prop.name} which conflicts with " \
              "the tool's pagination parameter. Rename the prop"
          end
        end
      end

      _validate_satisfiable_props!(klass, opts)
    end

    def _validate_satisfiable_props!(klass, opts)
      return unless klass.respond_to?(:literal_properties)

      context_keys = klass.context_mappings.keys.to_set
      visible = _compute_visible_filters(klass, opts[:only_filters], opts[:except_filters])
      excluded = _query_excluded_prop_names(klass, visible)

      klass.literal_properties.each do |prop|
        next unless excluded.include?(prop.name)
        next unless prop.required?
        next if context_keys.include?(prop.name)

        if _ref_type?(prop.type)
          raise ArgumentError, "prop :#{prop.name} (_Ref) is auto-excluded from the tool schema " \
            "but is required with no default and no context mapping — the tool could never execute"
        else
          raise ArgumentError, "excluding filter :#{prop.name} hides required prop :#{prop.name} " \
            "which has no default and no context mapping — the tool could never execute"
        end
      end
    end

    def _build_query_tool(klass, scope:, serialize:, limit: 50, only_filters: nil, except_filters: nil, only_sorts: nil)
      max_limit = limit
      scope_lambda = scope
      serialize_lambda = serialize

      visible_filters = _compute_visible_filters(klass, only_filters, except_filters)
      allowed_sorts = only_sorts ? only_sorts.map(&:to_sym) : klass.sorts

      schema = _query_params_schema(klass, visible_filters, allowed_sorts, max_limit)
      tool_desc = _query_tool_description(klass, visible_filters, allowed_sorts, max_limit)
      tool_name = "dex_query_#{(klass.name || "query").gsub("::", "_").downcase}"

      stripped_param_keys = klass.context_mappings.keys.to_set
      invisible_filters = klass.filters.to_set - visible_filters.to_set
      stripped_param_keys.merge(invisible_filters)

      query_class = klass

      Class.new(RubyLLM::Tool) do
        define_method(:name) { tool_name }
        define_method(:description) { tool_desc }
        define_method(:params_schema) { schema }

        define_method(:execute) do |**params|
          params = params.transform_keys(&:to_sym)

          req_limit = [(params.delete(:limit) || max_limit).to_i, max_limit].min
          req_limit = max_limit if req_limit <= 0
          req_offset = [params.delete(:offset).to_i, 0].max

          sort_value = params.delete(:sort)&.to_s
          if sort_value && !sort_value.empty?
            bare = sort_value.delete_prefix("-").to_sym
            valid = allowed_sorts.include?(bare)
            if valid && sort_value.start_with?("-")
              sort_def = query_class._sort_registry[bare]
              valid = false if sort_def&.custom
            end
            sort_value = nil unless valid
          else
            sort_value = nil
          end

          stripped_param_keys.each { |k| params.delete(k) }

          injected_scope = scope_lambda.call

          overrides = {}
          overrides[:sort] = sort_value if sort_value
          query = query_class.from_params(params, scope: injected_scope, **overrides)

          records = query.resolve

          total = begin
            result = records.count
            result.is_a?(Integer) ? result : nil
          rescue
            nil
          end

          records = records.offset(req_offset).limit(req_limit)

          serialized = records.map { |r| serialize_lambda.call(r) }

          { records: serialized, total: total, limit: req_limit, offset: req_offset }
        rescue ArgumentError, Literal::TypeError => e
          { error: "invalid_params", message: e.message }
        rescue => e
          { error: "query_failed", message: e.message }
        end
      end.new
    end

    def _query_tool_description(klass, visible_filters, allowed_sorts, max_limit)
      parts = []
      text = klass.description || klass.name || "Query"
      parts << (text.end_with?(".") ? text : "#{text}.")

      if visible_filters.any?
        filter_descs = visible_filters.map { |f| _query_filter_desc(klass, f) }
        parts << "Filters: #{filter_descs.join(", ")}."
      end

      if allowed_sorts.any?
        default_sort = klass._sort_default
        sort_descs = allowed_sorts.map do |s|
          bare_default = default_sort&.delete_prefix("-")
          if bare_default && bare_default.to_sym == s
            "#{s} (default: #{default_sort})"
          else
            s.to_s
          end
        end
        parts << "Sorts: #{sort_descs.join(", ")}."
      end

      parts << "Returns up to #{max_limit} results per page. Use offset to paginate."

      parts.join("\n")
    end

    def _query_filter_desc(klass, filter_name)
      descs = klass.respond_to?(:prop_descriptions) ? klass.prop_descriptions : {}
      prop_desc = descs[filter_name]

      prop = klass.literal_properties.find { |p| p.name == filter_name }
      return filter_name.to_s unless prop

      inner_type = prop.type
      inner_type = inner_type.type if inner_type.is_a?(Literal::Types::NilableType)

      if inner_type.respond_to?(:primitives) && inner_type.primitives&.any?
        values = inner_type.primitives.to_a.map(&:to_s)
        "#{filter_name} (#{_join_with_or(values)})"
      elsif prop_desc
        "#{filter_name} (#{prop_desc})"
      else
        filter_name.to_s
      end
    end

    def _join_with_or(values)
      case values.size
      when 1 then values.first
      when 2 then "#{values.first} or #{values.last}"
      else "#{values[..-2].join(", ")}, or #{values.last}"
      end
    end

    def _query_params_schema(klass, visible_filters, allowed_sorts, max_limit)
      properties = {}
      required = []

      excluded = _query_excluded_prop_names(klass, visible_filters)
      descs = klass.respond_to?(:prop_descriptions) ? klass.prop_descriptions : {}

      if klass.respond_to?(:literal_properties)
        klass.literal_properties.each do |prop|
          next if excluded.include?(prop.name)

          prop_desc = descs[prop.name]
          schema = TypeSerializer.to_json_schema(prop.type, desc: prop_desc)
          properties[prop.name.to_s] = schema
          required << prop.name.to_s if prop.required?
        end
      end

      if allowed_sorts.any?
        sort_values = []
        allowed_sorts.each do |s|
          sort_def = klass._sort_registry[s]
          sort_values << s.to_s
          sort_values << "-#{s}" unless sort_def.custom
        end

        default_sort = klass._sort_default
        sort_desc = "Sort order. Prefix with - for descending."
        sort_desc += " Default: #{default_sort}" if default_sort

        properties["sort"] = {
          type: "string",
          enum: sort_values,
          description: sort_desc
        }
      end

      properties["limit"] = {
        type: "integer",
        description: "Maximum number of results (default: #{max_limit}, max: #{max_limit})"
      }
      properties["offset"] = {
        type: "integer",
        description: "Number of results to skip (default: 0)"
      }

      result = { "$schema": "https://json-schema.org/draft/2020-12/schema" }
      result[:type] = "object"
      result[:properties] = properties
      result[:required] = required unless required.empty?
      result[:additionalProperties] = false
      result
    end

    def _compute_visible_filters(klass, only_filters, except_filters)
      context_keys = klass.context_mappings.keys.to_set

      filters = klass.filters.dup
      filters.reject! { |f| context_keys.include?(f) }
      filters.reject! do |f|
        prop = klass.literal_properties.find { |p| p.name == f }
        prop && _ref_type?(prop.type)
      end

      if only_filters
        only_set = only_filters.map(&:to_sym).to_set
        filters.select! { |f| only_set.include?(f) }
      elsif except_filters
        except_set = except_filters.map(&:to_sym).to_set
        filters.reject! { |f| except_set.include?(f) }
      end

      filters
    end

    def _query_excluded_prop_names(klass, visible_filters)
      return Set.new unless klass.respond_to?(:literal_properties)

      context_keys = klass.context_mappings.keys.to_set
      visible_set = visible_filters.to_set
      all_filters = klass.filters.to_set

      excluded = Set.new
      excluded.merge(context_keys)

      klass.literal_properties.each do |prop|
        excluded << prop.name if _ref_type?(prop.type)
      end

      invisible_filters = all_filters - visible_set
      excluded.merge(invisible_filters)

      excluded
    end

    def _ref_type?(type)
      return true if type.is_a?(Dex::RefType)
      return _ref_type?(type.type) if type.respond_to?(:type)

      false
    end

    # --- Explain tool ---

    def _build_explain_tool
      Class.new(RubyLLM::Tool) do
        define_method(:name) { "dex_explain" }
        define_method(:description) { "Check if an operation can be executed with given params, without running it." }
        define_method(:params_schema) do
          {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            type: "object",
            properties: {
              "operation" => { type: "string", description: "Operation class name (e.g. 'Order::Place')" },
              "params" => { type: "object", description: "Params to check" }
            },
            required: ["operation"],
            additionalProperties: false
          }
        end

        define_method(:execute) do |operation:, params: {}|
          op_class = Dex::Operation.registry.find { |klass| klass.name == operation }
          return { error: "unknown_operation", message: "Operation '#{operation}' not found in registry" } unless op_class

          coerced = params.transform_keys(&:to_sym)
          info = op_class.explain(**coerced)
          {
            callable: info[:callable],
            guards: info[:guards],
            once: info[:once],
            lock: info[:lock]
          }
        end
      end.new
    end

    private_class_method :_require_ruby_llm!, :_build_tool, :_tool_description, :_build_explain_tool,
      :_reject_unknown_options!, :_validate_query_tool_options!, :_validate_satisfiable_props!,
      :_build_query_tool, :_query_tool_description, :_query_filter_desc, :_join_with_or,
      :_query_params_schema, :_compute_visible_filters, :_query_excluded_prop_names, :_ref_type?
  end
end
