# GraphQL Operation Linter

Validate GraphQL operations against a schema, resolve shared fragments across files, and apply project conventions such as names, selection depth, and deprecated API usage.

## Installation

This gem is unreleased and requires Ruby 3.3 or later. Place a
`graphql-lint_core` checkout beside this repository or set
`GRAPHQL_LINT_CORE_PATH` to its location. Bundler uses RubyGems when a local Core
checkout is unavailable.

```sh
bundle install
```

## Quick start

```sh
bundle exec ruby exe/graphql-operation-lint check 'operations/**/*.{graphql,gql}' --schema schema.graphql
```

Omit `--schema` to check document syntax, fragment resolution, names, and structure without schema-specific rules.

Run `init --preset strict` to create `.graphql-operation-lint.yml`. Set the source paths before running `check`.

```yaml
version: 1
extends: [recommended]
schema:
  sources: [schema.graphql]
documents:
  include: ['operations/**/*.{graphql,gql}']
  exclude: ['operations/generated/**']
  fragment_resolution: global
rules:
  selection-set-depth:
    options: { max: 8 }
  no-deprecated: error
```

Use `rules` to list available rules and `explain no-deprecated` for details. Choose `strict` for filename, document layout, and selection limits. Choose `all` to enable every rule with its default options.

```sh
bundle exec ruby exe/graphql-operation-lint check --format github --format sarif:operations.sarif
```

The CLI exits with 0 for success, 1 for findings that reach the failure threshold, 2 for invalid configuration or unusable input, and 3 for an internal error. The default threshold is `error`.

## Ruby API

```ruby
require "graphql/operation_lint"

result = GraphQL::OperationLint.lint_documents(
  schema: "sdl:schema.graphql",
  documents: {
    "GetUser.graphql" => "query GetUser { user { id name } }"
  }
)

result.reportable.each { |diagnostic| puts diagnostic.message }
exit result.exit_status
```

Use `GraphQL::OperationLint.run(config: ".graphql-operation-lint.yml")` to load files through configuration. The config `require` option and the `ruby:` schema source execute Ruby code. Use trusted files and review their changes before running them in CI.

## Development

Run `bundle exec rake test build` at this repository's root. This gem has its
own version and accepts Core 0.1.x. Before Core is published, GitHub CI can
use a public Core checkout named by the `GRAPHQL_LINT_CORE_REPOSITORY`
repository variable (`owner/repository`). The release workflow resolves Core
from RubyGems.

Minitest and RSpec groups can include `GraphQL::OperationLint::TestHelper` after
requiring `graphql/operation_lint/test_helper`. Its `lint_fixture(directory)`
method reads fixture documents and uses `schema.graphql` when present.

## License

[MIT](LICENSE.txt)
