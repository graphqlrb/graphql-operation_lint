# frozen_string_literal: true

module GraphQL
  module OperationLint
    class SelectionResolver
      Nodes = GraphQL::Language::Nodes

      def initialize(index, document_set)
        @index = index
        @document_set = document_set
      end

      def selected_fields(node, type)
        concrete = %i[interface union].include?(type.kind) ? type.possible_types : [type.name]
        concrete = [type.name] if concrete.empty?
        concrete.map { |name| resolve(node.selections, name) }.reduce(:&)
      end

      private

      def resolve(selections, name)
        visited = {}
        fields = []
        stack = selections.reverse
        until stack.empty?
          selection = stack.pop
          case selection
          when Nodes::Field
            fields << selection.name
          when Nodes::InlineFragment
            condition = selection.type&.name
            stack.concat(selection.selections.reverse) if condition.nil? || applies?(condition, name)
          when Nodes::FragmentSpread
            fragment = @document_set.resolve(selection)
            next unless fragment && !visited[fragment]

            visited[fragment] = true
            stack.concat(fragment.node.selections.reverse) if applies?(fragment.node.type.name, name)
          end
        end
        fields.uniq
      end

      def applies?(condition, name)
        condition == name || @index.types[condition]&.possible_types&.include?(name)
      end
    end
  end
end
