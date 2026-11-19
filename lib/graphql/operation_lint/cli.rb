# frozen_string_literal: true

require "graphql/operation_lint"

module GraphQL
  module OperationLint
    module CLI
      module_function

      def run(argv = ARGV, stdout: $stdout, stderr: $stderr)
        Core::CLI.run(OperationLint, argv, name: "graphql-operation-lint", defaults: DEFAULTS, presets: PRESETS,
          options: method(:add_options), stdout: stdout, stderr: stderr)
      end

      def add_options(parser, overrides, _arguments)
        document_globs = []
        schemas = []
        parser.on("--documents GLOB", "Read .graphql and .gql documents matching a glob.") do |glob|
          document_globs << glob
        end
        parser.on("--schema SOURCE", "Supply a schema source.") { |source| schemas << source }
        parser.on("--emit-generated-sdl PATH", "Write SDL generated from a Ruby schema or introspection.") do |path|
          (overrides["schema"] ||= {})["emit_generated_sdl"] = path
        end
        lambda do |positionals|
          document_globs.concat(positionals)
          positionals.clear
          (overrides["documents"] ||= {})["include"] = document_globs unless document_globs.empty?
          (overrides["schema"] ||= {})["sources"] = schemas unless schemas.empty?
        end
      end
    end
  end
end
