# frozen_string_literal: true

module GraphQL
  module OperationLint
    module Rules
      class NoDeprecated < Rule
        id "no-deprecated"
        category :deprecation
        description "Report deprecated fields, arguments, and literal input fields and enum values. Values supplied in variables are unavailable to static validation."
        default_severity :warning
        requires_schema true
        option :include, type: :string_list, default: %w[fields arguments input_fields enum_values]
        option :ignore, type: :coordinate_patterns, default: []
        message :deprecated, "`%{operation}` uses deprecated %{kind} `%{coordinate}`. Deprecation reason: %{reason}."
        suggestion :deprecated, "Migrate to the alternative described in the deprecation reason."

        KINDS = {
          on_field: ["fields", "field"],
          on_argument: ["arguments", "argument"],
          on_input_object_field: ["input_fields", "input field"],
          on_enum_literal: ["enum_values", "enum value"]
        }.freeze

        def self.resolve_options(raw)
          options = super
          unless (options[:include] - KINDS.values.map(&:first)).empty?
            raise Core::ConfigError, "no-deprecated.options.include contains an unknown member kind."
          end

          options
        end

        KINDS.each do |event_name, (option, kind)|
          define_method(event_name) do |event|
            next unless options[:include].include?(option)

            member = event.definition
            next unless member.respond_to?(:deprecation) && (deprecation = member.deprecation)
            next if options[:ignore].match?(event.coordinate)

            report(event, :deprecated, coordinate: event.coordinate, operation: event.document_definition.display_name,
              kind: kind, reason: deprecation.reason, data: { reason: deprecation.reason, kind: option })
          end
        end
      end

      class RequireSelections < Rule
        id "require-selections"
        category :selection
        description "Select the configured fields on types that define them."
        default_severity :warning
        requires_schema true
        option :fields, type: :string_list, default: ["id"]
        option :ignore_types, type: :coordinate_patterns, default: []
        message :missing, "The selection set on `%{type}` does not select `%{field}`."
        suggestion :missing, "Add a selection for `%{field}`."
        fingerprint_keys :field

        def setup(context)
          super
          @resolver = SelectionResolver.new(context.index, context.document_set)
        end

        def on_operation(event) = check(event)
        def on_fragment(event) = check(event)
        def on_inline_fragment(event) = check(event)
        def on_field(event) = check(event)

        private

        def check(event)
          type = event.type
          return unless type && !event.node.selections.empty?
          return if options[:ignore_types].match?(type.coordinate)

          required = options[:fields] & type.fields.keys
          return if required.empty?

          (required - @resolver.selected_fields(event.node, type)).each do |field|
            report(event, :missing, type: type.name, field: field, data: { field: field, type: type.name })
          end
        end
      end

      class NoDuplicateFields < Rule
        Nodes = GraphQL::Language::Nodes
        id "no-duplicate-fields"
        category :selection
        description "Avoid selecting a field twice in the same selection set with the same response key and arguments."
        default_severity :warning
        message :duplicate, "Field `%{field}` is selected more than once with the same response key and arguments."
        suggestion :duplicate, "Combine these selections into one field selection."

        def on_operation(event) = check(event)
        def on_fragment(event) = check(event)
        def on_inline_fragment(event) = check(event)
        def on_field(event) = check(event)

        private

        def check(event)
          seen = {}
          source = event.document_definition.source
          event.node.selections.grep(Nodes::Field).each do |field|
            response_key = field.alias || field.name
            key = [field.name, response_key, arguments(field.arguments)]
            first = seen[key] ||= field
            next if first.equal?(field)

            target = Target.new(location: source.location(field), name_location: source.name_location(field),
              operations: event.operations, path: event.path + [response_key],
              coordinate: event.type&.fields&.[](field.name)&.coordinate)
            report(target, :duplicate, field: response_key,
              related: [{ location: source.location(first), message: "First selection" }])
          end
        end

        def arguments(nodes)
          nodes.sort_by(&:name).map { |argument| [argument.name, value(argument.value)] }
        end

        def value(node)
          case node
          when Nodes::InputObject then [:object, arguments(node.arguments)]
          when Nodes::VariableIdentifier then [:variable, node.name]
          when Nodes::Enum then [:enum, node.name]
          when Nodes::NullValue then nil
          when Array then node.map { |item| value(item) }
          else node
          end
        end
      end

      class RestrictedFields < Rule
        id "restricted-fields"
        category :custom
        description "Limit the use of configured field, argument, and type coordinates."
        default_severity :error
        requires_schema true
        option :fields, type: :array, default: []
        message :restricted, "The schema element `%{coordinate}` is restricted."
        suggestion :restricted, "Use a permitted schema element at this location."

        def self.resolve_options(raw)
          options = super
          options[:fields] = options[:fields].map do |entry|
            unless entry.is_a?(Hash)
              raise Core::ConfigError, "Each restricted-fields.options.fields entry must be a mapping."
            end

            entry = entry.transform_keys(&:to_s)
            unknown = entry.keys - %w[coordinate allow_paths allow_operations message]
            if !unknown.empty? || !entry["coordinate"].is_a?(String) || entry["coordinate"].empty?
              raise Core::ConfigError, "Each restricted field needs a coordinate and accepts allow_paths, allow_operations, and message."
            end
            %w[allow_paths allow_operations].each do |key|
              next unless entry.key?(key)
              next if entry[key].is_a?(Array) && entry[key].all?(String)

              raise Core::ConfigError, "restricted-fields.options.fields.#{key} must be an array of strings."
            end
            if entry.key?("message") && !entry["message"].is_a?(String)
              raise Core::ConfigError, "restricted-fields.options.fields.message must be a string."
            end

            entry.merge("coordinate" => Core::CoordinatePattern.new(entry["coordinate"]))
          end
          options
        end

        def on_field(event)
          check(event, event.coordinate)
          check(event, event.type&.coordinate)
        end

        %i[argument fragment inline_fragment variable_definition input_object input_object_field].each do |kind|
          define_method(:"on_#{kind}") { |event| check(event, event.coordinate) }
        end

        private

        def check(event, coordinate)
          return unless coordinate

          options[:fields].each do |restriction|
            next unless restriction.fetch("coordinate").match?(coordinate)
            next if matching_glob?(restriction.fetch("allow_paths", []), event.location.path)

            denied = event.operations.reject do |name|
              matching_glob?(restriction.fetch("allow_operations", []), operation_name(name))
            end
            next if event.operations.any? && denied.empty?

            target = Target.new(location: event.location, name_location: event.name_location,
              operations: denied, path: event.path, coordinate: coordinate)
            if restriction["message"]
              report(target, :custom, text: restriction["message"], coordinate: coordinate)
            else
              report(target, :restricted, coordinate: coordinate)
            end
            break
          end
        end

        message :custom, "%{text}"
        suggestion :custom, "Use a permitted schema element at this location."

        def operation_name(display_name)
          return display_name if display_name.start_with?("<anonymous>")

          display_name.split("@", 2).first
        end
      end
    end
  end
end
