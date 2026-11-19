# frozen_string_literal: true

module GraphQL
  module OperationLint
    module Rules
      class OperationLimit < Rule
        def self.walk = [:operations]

        def self.resolve_options(raw)
          options = super
          maximum = options[:max]
          limits = maximum.is_a?(Hash) ? maximum.values : [maximum]
          unless limits.all? { |limit| limit.is_a?(Integer) && !limit.negative? }
            raise Core::ConfigError, "#{id}.options.max must contain nonnegative integers."
          end

          options
        end

        def on_operation(_event)
          @count = 0
          @locations = {}
        end

        def leave_operation(event)
          max = limit(event)
          return unless max && @count > max

          path = @deepest || []
          report(event, :exceeded, operation: event.operation, count: @count, max: max, path: path.join(" > "),
            data: { count: @count, max: max, path: path }, related: related)
        end

        private

        def limit(_event) = options[:max]
        def related = []
      end

      class SelectionSetDepth < OperationLimit
        id "selection-set-depth"
        category :structure
        description "An operation must stay within the configured field depth after expanding fragments."
        default_severity :warning
        option :max, type: :integer, default: 10
        option :ignore, type: :string_list, default: []
        option :count_introspection, type: :boolean, default: false
        message :exceeded, "Operation `%{operation}` reaches depth %{count}, exceeding %{max}. Deepest path: %{path}."
        suggestion :exceeded, "Split the operation or remove unnecessary nested selections."

        def on_operation(event)
          super
          @deepest = []
          @deepest_location = nil
        end

        def on_field(event)
          return if !options[:count_introspection] && event.ancestors.any? { |field| field.name.start_with?("__") }

          path = event.ancestors.reject { |field| options[:ignore].include?(field.name) }
          return if path.length <= @count

          @count = path.length
          @deepest = path.map(&:name)
          @deepest_location = event.location
        end

        private

        def related
          [{ location: @deepest_location, message: "Deepest field selection" }]
        end
      end

      class MaxAliases < OperationLimit
        id "max-aliases"
        category :structure
        description "An operation must stay within the configured number of aliased selections."
        default_severity :warning
        option :max, type: :integer, default: 10
        message :exceeded, "Operation `%{operation}` has %{count} aliases, exceeding %{max}."
        suggestion :exceeded, "Remove unnecessary aliases or split the operation."

        def on_field(event)
          return unless event.node.alias

          @count += 1
          location, count = @locations.fetch(event.document_definition, [event.location, 0])
          @locations[event.document_definition] = [location, count + 1]
        end

        private

        def related
          location, count = @locations.values.max_by(&:last)
          [{ location: location, message: "#{count} aliases in this definition" }]
        end
      end

      class MaxRootFields < OperationLimit
        id "max-root-fields"
        category :structure
        description "An operation must stay within the configured number of root fields."
        default_severity :warning
        option :max, type: :hash, default: { "query" => 10, "mutation" => 1, "subscription" => 1 }
        message :exceeded, "Operation `%{operation}` selects %{count} root fields, exceeding %{max}."
        suggestion :exceeded, "Split the root field selections across operations."

        def self.resolve_options(raw)
          options = super
          unless options[:max].keys.all? { |key| %w[query mutation subscription].include?(key.to_s) }
            raise Core::ConfigError, "max-root-fields.options.max accepts query, mutation, and subscription."
          end

          options
        end

        def on_field(event)
          @count += 1 if event.depth == 1
        end

        private

        def limit(event)
          options[:max][event.node.operation_type]
        end
      end

      class MaxSelections < OperationLimit
        id "max-selections"
        category :structure
        description "An operation must stay within the configured total number of field selections."
        default_severity :warning
        option :max, type: :integer, default: 500
        message :exceeded, "Operation `%{operation}` selects %{count} fields, exceeding %{max}."
        suggestion :exceeded, "Remove unnecessary field selections or split the operation."

        def on_field(_event)
          @count += 1
        end
      end
    end
  end
end
