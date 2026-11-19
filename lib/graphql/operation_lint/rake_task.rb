# frozen_string_literal: true

require "graphql/operation_lint"
require "rake/tasklib"

module GraphQL
  module OperationLint
    # @api public
    class RakeTask < ::Rake::TaskLib
      attr_accessor :config, :overrides

      def initialize(name = :operation_lint)
        @overrides = {}
        yield self if block_given?

        desc "Lint GraphQL operations"
        task name do
          result = OperationLint.run(config: config, overrides: overrides)
          puts Core::Formatter.render("text", result)
          exit result.exit_status unless result.exit_status.zero?
        end
      end
    end
  end
end
