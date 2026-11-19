# frozen_string_literal: true

require "graphql/operation_lint"

module GraphQL
  module OperationLint
    # Include in a Minitest test or RSpec example group.
    # @api public
    module TestHelper
      def lint_fixture(directory, rules: {}, config: nil)
        directory = File.expand_path(directory)
        schema = File.join(directory, "schema.graphql")
        documents = Dir.glob("**/*.{graphql,gql}", base: directory).sort.filter_map do |path|
          next if path == "schema.graphql"

          [path, File.binread(File.join(directory, path))]
        end.to_h
        OperationLint.lint_documents(documents: documents, schema: (schema if File.file?(schema)), rules: rules, config: config)
      end
    end
  end
end
