# frozen_string_literal: true

module GraphQL
  module OperationLint
    # @api public
    class Rule < Core::Rule
      Target = Data.define(:location, :name_location, :operations, :path, :coordinate)

      def self.walk(*modes)
        @walk_modes = modes.flatten unless modes.empty?
        @walk_modes || (superclass < Rule ? superclass.walk : [:definitions])
      end

      private

      def definition_target(definition)
        Target.new(
          location: definition.location,
          name_location: definition.source.name_location(definition.node),
          operations: @context.document_set.operations_for(definition),
          path: ["#{definition.kind} #{definition.display_name}"],
          coordinate: nil
        )
      end

      def matching_glob?(patterns, value)
        patterns.any? { |pattern| File.fnmatch?(pattern, value, Core::Documents::FileSource::FLAGS) }
      end
    end
  end
end
