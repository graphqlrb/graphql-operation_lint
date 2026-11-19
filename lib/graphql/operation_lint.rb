# frozen_string_literal: true

require "graphql/lint_core"
require "psych"
require_relative "operation_lint/version"

module GraphQL
  # @api public
  module OperationLint
    Core = GraphQL::LintCore
    NAME = "graphql-operation_lint"
    CONFIG_FILE = ".graphql-operation-lint.yml"
    ROOT = File.expand_path("../..", __dir__)
    DEFAULTS = {
      "extends" => ["recommended"],
      "schema" => { "sources" => [], "prelude" => [], "skip_checks" => [] },
      "documents" => { "include" => [], "exclude" => [], "fragment_resolution" => "global" },
      "validation" => { "timeout" => 5, "max_errors" => 100 }
    }.freeze

    autoload :CLI, "graphql/operation_lint/cli"
    autoload :RakeTask, "graphql/operation_lint/rake_task"
  end
end

require_relative "operation_lint/rule"
require_relative "operation_lint/selection_resolver"
require_relative "operation_lint/rules/documents"
require_relative "operation_lint/rules/selections"
require_relative "operation_lint/rules/structure"
require_relative "operation_lint/rules/spec_bridge"
require_relative "operation_lint/runner"

module GraphQL
  module OperationLint
    BUILT_INS = [
      Rules::UniqueOperationName, Rules::UniqueFragmentName, Rules::NoUnusedFragments, Rules::NoOnePlaceFragments,
      Rules::NoDeprecated, Rules::NoAnonymousOperations, Rules::NamingConvention, Rules::MatchDocumentFilename,
      Rules::MaxOperationsPerFile, Rules::LoneExecutableDefinition, Rules::SelectionSetDepth, Rules::MaxAliases,
      Rules::MaxRootFields, Rules::MaxSelections, Rules::RequireSelections, Rules::NoDuplicateFields, Rules::RestrictedFields
    ].to_h { |rule| [rule.id, rule] }.merge(Rules::SpecBridge::RULES).freeze
    PRESETS = %w[recommended strict all].to_h do |name|
      data = Psych.safe_load_file(File.join(ROOT, "presets", "#{name}.yml"), aliases: false)
      [name, data]
    end
    PRESETS.fetch("recommended").fetch("rules").merge!(Rules::SpecBridge::RULES.transform_values { "error" })
    PRESETS.freeze

    @rules = BUILT_INS
    @registration_lock = Mutex.new

    class << self
      attr_reader :rules

      # @api public
      def register_rule(rule)
        unless rule.is_a?(Class) && rule < Rule && rule.id&.match?(%r{\A[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*\z})
          raise Core::ConfigError, "Custom operation rules require a namespace and must inherit from OperationLint::Rule."
        end

        @registration_lock.synchronize do
          raise Core::ConfigError, "Rule `#{rule.id}` is already registered." if @rules.key?(rule.id)

          @rules = @rules.merge(rule.id => rule).freeze
        end
        rule
      end

      # @api public
      def run(config: nil, overrides: {})
        Runner.new(config: config, overrides: overrides).run
      end

      # @api public
      def lint_documents(documents:, schema: nil, rules: {}, config: nil, overrides: {})
        settings = Core::Config.merge(Core::Config.stringify(overrides), "rules" => Core::Config.stringify(rules))
        Runner.new(config: config, overrides: settings, documents: documents, schema: schema).run
      end
    end
  end
end
