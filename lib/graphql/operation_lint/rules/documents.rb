# frozen_string_literal: true

module GraphQL
  module OperationLint
    module Rules
      class UniqueOperationName < Rule
        id "unique-operation-name"
        category :operation
        description "Operation names must be unique in the selected scope."
        default_severity :error
        option :scope, type: :enum, values: %w[project directory], default: "project"
        message :duplicate, "Operation `%{name}` is already defined."
        suggestion :duplicate, "Use a name that is unique in the selected scope."

        def finish(set)
          seen = {}
          set.operations.each do |operation|
            next unless operation.name

            key = options[:scope] == "directory" ? [File.dirname(operation.path), operation.name] : operation.name
            first = seen[key] ||= operation
            next if first.equal?(operation)

            report(definition_target(operation), :duplicate, location: :name, name: operation.name,
              related: [{ location: first.location, message: "First definition" }])
          end
        end
      end

      class UniqueFragmentName < Rule
        id "unique-fragment-name"
        category :fragment
        description "Fragment names must be unique in the document set."
        default_severity :error
        message :duplicate, "Fragment `%{name}` is already defined."
        suggestion :duplicate, "Use a unique name and update the corresponding fragment spreads."

        def finish(set)
          seen = {}
          set.fragments.each do |fragment|
            first = seen[fragment.name] ||= fragment
            next if first.equal?(fragment)

            report(definition_target(fragment), :duplicate, location: :name, name: fragment.name,
              related: [{ location: first.location, message: "First definition" }])
          end
        end
      end

      class NoUnusedFragments < Rule
        id "no-unused-fragments"
        category :fragment
        description "Every fragment must be reachable from an operation."
        default_severity :warning
        option :ignore, type: :string_list, default: []
        option :ignore_paths, type: :glob_list, default: []
        message :unused, "Fragment `%{name}` is unused."
        suggestion :unused, "Remove the fragment or spread it from an operation."

        def finish(set)
          set.fragments.each do |fragment|
            next unless set.operations_for(fragment).empty?
            next if matching_glob?(options[:ignore], fragment.name) || matching_glob?(options[:ignore_paths], fragment.path)

            report(definition_target(fragment), :unused, location: :name, name: fragment.name)
          end
        end
      end

      class NoOnePlaceFragments < Rule
        id "no-one-place-fragments"
        category :fragment
        description "A fragment spread only once can be inlined."
        default_severity :warning
        message :single_spread, "Fragment `%{name}` is spread in only one place."
        suggestion :single_spread, "Inline the fragment at its spread."

        def finish(set)
          by_definition = set.spreads.group_by { |node| set.resolve(node) }
          by_definition.each do |fragment, spreads|
            next unless fragment && spreads.length == 1

            spread = spreads.first
            owner = set.owner(spread)
            report(definition_target(fragment), :single_spread, location: :name, name: fragment.name,
              related: [{ location: owner.source.location(spread), message: "Only spread" }])
          end
        end
      end

      class NoAnonymousOperations < Rule
        id "no-anonymous-operations"
        category :operation
        description "Every operation must have a name."
        default_severity :error
        message :anonymous, "The operation `%{operation}` has no name."
        suggestion :anonymous, "Give the operation a unique name."

        def on_operation(event)
          return if event.node.name

          report(event, :anonymous, operation: event.operation)
        end
      end

      class NamingConvention < Rule
        id "naming-convention"
        category :operation
        description "Operation, fragment, and variable names must follow the configured conventions."
        default_severity :warning
        option :operations, type: :hash, default: { "style" => "PascalCase" }
        option :query, type: :hash, default: {}
        option :mutation, type: :hash, default: {}
        option :subscription, type: :hash, default: {}
        option :fragments, type: :hash, default: { "style" => "PascalCase" }
        option :variables, type: :hash, default: { "style" => "camelCase" }
        option :fragment_type_prefix, type: :boolean, default: false
        message :invalid, "The %{kind} name `%{name}` does not follow the naming convention."
        suggestion :invalid, "Choose a name such as `%{candidate}`."
        message :fragment_prefix, "Fragment `%{name}` does not start with its type condition `%{type}`."
        suggestion :fragment_prefix, "Rename the fragment to `%{candidate}` and update its spreads."

        def self.resolve_options(raw)
          options = super
          %i[operations query mutation subscription fragments variables].each do |key|
            options[key] = Core::Naming.validate(options.fetch(key))
          end
          options
        end

        def on_operation(event)
          rule = options[:operations].merge(options.fetch(event.node.operation_type.to_sym, {}))
          check(event, "operation", rule)
        end

        def on_fragment(event)
          check(event, "fragment", options[:fragments])
          name = event.node.name
          type = event.node.type.name
          return unless options[:fragment_type_prefix] && !name.start_with?(type)

          report(event, :fragment_prefix, location: :name, name: name, type: type,
            candidate: type + Core::Naming.convert(name, "PascalCase"))
        end

        def on_variable_definition(event)
          check(event, "variable", options[:variables])
        end

        private

        def check(event, kind, rule)
          name = event.node.name
          return if !name || Core::Naming.valid?(name, rule)

          report(event, :invalid, location: :name, name: name, kind: kind, candidate: Core::Naming.replacement(name, rule))
        end
      end

      class MatchDocumentFilename < Rule
        id "match-document-filename"
        category :file
        description "Each document filename must reflect the name of its first definition."
        default_severity :warning
        option :style, type: :enum, values: %w[as_is PascalCase camelCase kebab-case snake_case], default: "as_is"
        option :suffixes, type: :hash, default: {}
        option :check_fragments, type: :boolean, default: true
        message :mismatch, "Filename `%{actual}` does not follow the naming convention. Expected `%{expected}`."
        suggestion :mismatch, "Rename the file to `%{expected}`."

        def self.resolve_options(raw)
          options = super
          suffixes = options[:suffixes]
          valid_keys = %w[query mutation subscription fragment]
          unless suffixes.all? { |type, suffix| valid_keys.include?(type.to_s) && suffix.is_a?(String) }
            raise Core::ConfigError, "match-document-filename.options.suffixes must map definition kinds to strings."
          end

          options
        end

        def on_document(document)
          definition = document.definitions.find(&:operation?)
          definition ||= document.definitions.find(&:fragment?) if options[:check_fragments]
          return unless definition&.name

          actual = File.basename(document.path)
          expected = Core::Naming.convert(definition.name, options[:style]) +
            options[:suffixes].fetch(definition.kind, "") + File.extname(actual)
          return if actual == expected

          report(definition_target(definition), :mismatch, actual: actual, expected: expected,
            data: { expected_filename: expected })
        end
      end

      class MaxOperationsPerFile < Rule
        id "max-operations-per-file"
        category :file
        description "Each file must stay within the configured number of operations."
        default_severity :warning
        option :max, type: :integer, default: 1
        option :count_fragments, type: :boolean, default: false
        message :exceeded, "The file has %{count} definitions, exceeding the limit of %{max}."
        suggestion :exceeded, "Split the definitions into separate files."

        def self.resolve_options(raw)
          options = super
          raise Core::ConfigError, "max-operations-per-file.options.max must be nonnegative." if options[:max].negative?

          options
        end

        def on_document(document)
          definitions = document.definitions
          definitions = definitions.select(&:operation?) unless options[:count_fragments]
          count = definitions.length
          max = options[:max]
          return unless count > max

          report(definition_target(definitions.fetch(max)), :exceeded, count: count, max: max, data: { count: count, max: max })
        end
      end

      class LoneExecutableDefinition < Rule
        id "lone-executable-definition"
        category :file
        description "Executable definitions must be in separate files."
        default_severity :warning
        option :ignore, type: :string_list, default: []
        message :mixed, "This file contains more than one executable definition."
        suggestion :mixed, "Move each definition to its own file."

        def on_document(document)
          definitions = document.definitions.reject { |definition| options[:ignore].include?(definition.kind) }
          return if definitions.length <= 1

          report(definition_target(definitions[1]), :mixed,
            related: [{ location: definitions.first.location, message: "First definition" }])
        end
      end
    end
  end
end
