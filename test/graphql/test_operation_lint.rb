# frozen_string_literal: true

require "minitest/autorun"
require "graphql/operation_lint"

class OperationLintTest < Minitest::Test
  SCHEMA = <<~GRAPHQL
    type Query {
      user(filter: Search, oldArgument: Int @deprecated(reason: "Use filter")): User
      other: String
    }
    type User {
      id: ID!
      name: String
      legacy: String @deprecated(reason: "Use name")
      friends: [User!]!
    }
    input Search {
      oldFilter: Tag @deprecated(reason: "Use tag")
      tag: Tag
    }
    enum Tag {
      OLD @deprecated(reason: "Use NEW")
      NEW
    }
  GRAPHQL

  def test_operation_api_works_without_loading_other_products
    assert defined?(GraphQL::OperationLint), "The gem should expose GraphQL::OperationLint"
    assert_respond_to GraphQL::OperationLint, :lint_documents
  end

  def test_recommended_rules_run_without_schema
    result = lint({ "a.gql" => "{ user { name name } ...Unknown }" })
    assert_equal 1, result.exit_status
    %w[no-anonymous-operations no-duplicate-fields operation/schema-less spec/known-fragment-names].each do |id|
      assert_includes ids(result), id
    end
    refute_includes ids(result), "spec/fields-on-correct-type"
    assert_match(/Skipped \d+ rules because no schema was supplied\./, diagnostic(result, "operation/schema-less").message)
  end

  def test_spec_rules_can_be_disabled
    documents = { "query.gql" => "query GetUser { user { missing } }" }
    assert_includes ids(lint(documents, schema: schema)), "spec/fields-on-correct-type"
    assert_empty ids(lint(documents, schema: schema, rules: { "spec/fields-on-correct-type" => "off" }))
  end

  def test_spec_rule_uses_configured_severity_and_reports_how_to_fix_unresolved_fragment
    result = lint({ "a.gql" => "query Q { ...Missing }" }, rules: { "spec/known-fragment-names" => "warning" })
    finding = diagnostic(result, "spec/known-fragment-names")

    assert_equal :warning, finding.severity
    assert_equal "Fragment `Missing` could not be resolved.", finding.message
    assert_equal "Update the document to satisfy the GraphQL validation rule.", finding.suggestion
  end

  def test_duplicates_report_related_definition_and_can_use_directory_scope
    documents = {
      "a/user.gql" => "query GetUser { user { name } } fragment Shared on User { name }",
      "b/user.gql" => "query GetUser { user { id } } fragment Shared on User { id }"
    }
    result = lint(documents)
    duplicates = result.diagnostics.select { |diagnostic| diagnostic.rule_id.start_with?("unique-") }
    assert_equal %w[unique-operation-name unique-fragment-name], duplicates.map(&:rule_id)
    duplicates.each do |diagnostic|
      assert_equal "b/user.gql", diagnostic.location.path
      assert_equal "a/user.gql", diagnostic.related.first.fetch(:location).path
    end
    scoped = lint(documents, rules: { "unique-operation-name" => { options: { scope: "directory" } } })
    refute_includes ids(scoped), "unique-operation-name"
  end

  def test_unused_and_one_place_fragments_follow_actual_spread_nodes
    documents = {
      "a.gql" => "query GetUser { user { ...Used ...Used } }",
      "fragments.gql" => "fragment Used on User { ...Leaf } fragment Leaf on User { name } fragment Unused on User { ...Dead }",
      "lib/dead.gql" => "fragment Dead on User { id }"
    }
    result = lint(documents, rules: {
      "no-unused-fragments" => { options: { ignore_paths: ["lib/**"] } },
      "no-one-place-fragments" => "warning"
    })
    assert_match(/Unused/, diagnostic(result, "no-unused-fragments").message)
    assert_equal 1, ids(result).count("no-unused-fragments")
    assert_match(/Leaf/, diagnostic(result, "no-one-place-fragments").message)
  end

  def test_deprecated_literal_members_are_reported_once_with_all_operations
    documents = {
      "query.gql" => "query GetUser { ...Shared } query ListUsers { ...Shared }",
      "fragment.gql" => "fragment Shared on Query { user(oldArgument: 1, filter: { oldFilter: OLD }) { legacy } }"
    }
    result = lint(documents, schema: schema)
    findings = result.diagnostics.select { |diagnostic| diagnostic.rule_id == "no-deprecated" }
    assert_equal %w[Query.user(oldArgument:) Search.oldFilter Tag.OLD User.legacy], findings.map(&:coordinate)
    assert findings.all? { |diagnostic| diagnostic.operations == %w[GetUser ListUsers] }
    assert_match(/uses deprecated field `User.legacy`\. Deprecation reason: Use name\./, findings.last.message)
    assert_equal "Migrate to the alternative described in the deprecation reason.", findings.last.suggestion
  end

  def test_naming_and_filename_options
    documents = { "queries\\wrong.gql" => "query get_user($Bad: Int) { user { name } } fragment Details on User { id }" }
    result = lint(documents, rules: {
      "naming-convention" => { options: { query: { suffix: "Query" }, fragment_type_prefix: true } },
      "match-document-filename" => { options: { style: "kebab-case", suffixes: { query: ".query" } } }
    })
    assert_equal 3, ids(result).count("naming-convention")
    assert_match(/get-user.query.gql/, diagnostic(result, "match-document-filename").message)
  end

  def test_file_rules_can_count_and_ignore_fragments
    documents = { "user.gql" => "query GetUser { user { ...Parts } } fragment Parts on User { name }" }
    result = lint(documents, rules: {
      "max-operations-per-file" => { options: { count_fragments: true } },
      "lone-executable-definition" => { options: { ignore: ["fragment"] } }
    })
    assert_includes ids(result), "max-operations-per-file"
    refute_includes ids(result), "lone-executable-definition"
  end

  def test_structural_limits_expand_fragments_and_count_aliases
    documents = {
      "query.gql" => "query GetUser { ...Both other }",
      "details.gql" => "fragment Both on Query { a: user { ... on User { friends { name } } } b: user { ...Names ...Names } } fragment Names on User { aliasName: name }"
    }
    result = lint(documents, rules: {
      "selection-set-depth" => { options: { max: 2 } },
      "max-aliases" => { options: { max: 3 } },
      "max-root-fields" => { options: { max: { query: 2 } } },
      "max-selections" => { options: { max: 6 } }
    })
    assert_equal 3, diagnostic(result, "selection-set-depth").data.fetch(:count)
    assert_equal "details.gql", diagnostic(result, "selection-set-depth").related.first.fetch(:location).path
    assert_equal 4, diagnostic(result, "max-aliases").data.fetch(:count)
    assert_equal 3, diagnostic(result, "max-root-fields").data.fetch(:count)
    assert_equal 7, diagnostic(result, "max-selections").data.fetch(:count)
  end

  def test_require_selections_reuses_fragments_on_the_same_type
    documents = {
      "query.gql" => "query GetUser { user { ...Identity friends { name } } }",
      "id.gql" => "fragment Identity on User { ... on User { id } }"
    }
    result = lint(documents, schema: schema, rules: { "require-selections" => "warning" })
    findings = result.diagnostics.select { |diagnostic| diagnostic.rule_id == "require-selections" }
    assert_equal 1, findings.length
    assert_equal "User.friends", findings.first.coordinate
  end

  def test_duplicate_arguments_are_compared_without_source_order
    docs = { "q.gql" => <<~GRAPHQL }
      query Q {
        user(filter: { tag: NEW, oldFilter: NEW }, oldArgument: 1) { name }
        user(oldArgument: 1, filter: { oldFilter: NEW, tag: NEW }) { id }
        otherUser: user { name }
      }
    GRAPHQL
    assert_equal 1, ids(lint(docs)).count("no-duplicate-fields")
  end

  def test_restricted_fields_respect_operation_and_path_allowlists
    documents = {
      "q.gql" => "query InternalRead { ...Shared } query ClientRead { ...Shared }",
      "fragment.gql" => "fragment Shared on Query { user(oldArgument: 1) { legacy } }"
    }
    rule = { options: { fields: [
      { coordinate: "User.legacy", allow_operations: ["Internal*"], message: "Use User.name." },
      { coordinate: "Query.user(oldArgument:)", allow_paths: ["fragment.gql"] }
    ] } }
    result = lint(documents, schema: schema, rules: { "restricted-fields" => rule })
    matches = result.diagnostics.select { |diagnostic| diagnostic.rule_id == "restricted-fields" }
    assert_equal ["User.legacy"], matches.map(&:coordinate)
    assert_equal ["ClientRead"], matches.first.operations
    assert_equal "Use User.name.", matches.first.message
  end

  def test_custom_definition_rule_receives_typed_fields_and_can_report_once
    rule = Class.new(GraphQL::OperationLint::Rule) do
      id "app/limit-friends"
      category :custom
      default_severity :error
      requires_schema
      walk :definitions
      message :violation, "Avoid `%{coordinate}`."

      def on_field(field)
        report(field, :violation, location: :name) if field.coordinate == "User.friends"
      end
    end
    GraphQL::OperationLint.register_rule(rule)

    documents = {
      "q.gql" => "query Q { ...Shared } query R { ...Shared }",
      "shared.gql" => "fragment Shared on Query { user { friends { id } } }"
    }
    options = { "app/limit-friends" => "error" }
    result = lint(documents, schema: schema, rules: options)
    finding = result.diagnostics.select { |diagnostic| diagnostic.rule_id == "app/limit-friends" }
    assert_equal 1, finding.size
    assert_equal %w[Q R], finding.first.operations
    assert_equal "shared.gql", finding.first.location.path
    assert_equal "Avoid `User.friends`.", finding.first.message
    refute_includes ids(lint(documents, rules: options)), "app/limit-friends"
  end

  def test_invalid_options_and_yaml_keys_are_configuration_errors
    assert_equal 2, lint({ "q.gql" => "query Q { other }" }, rules: {
      "selection-set-depth" => { options: { max: -1 } }
    }).exit_status
    assert_equal 2, lint({ "q.gql" => "query Q { other }" }, config: {
      documents: { fragment_resoluton: "same_file" }
    }).exit_status
  end

  private

  def lint(documents, schema: nil, rules: {}, config: nil)
    assert GraphQL::OperationLint.respond_to?(:lint_documents)
    GraphQL::OperationLint.lint_documents(documents: documents, schema: schema, rules: rules, config: config)
  end

  def schema
    @schema ||= GraphQL::Schema.from_definition(SCHEMA)
  end

  def ids(result)
    result.diagnostics.map(&:rule_id)
  end

  def diagnostic(result, id)
    result.diagnostics.find { |item| item.rule_id == id } ||
      flunk("Expected #{id}, got #{result.diagnostics.map { |item| [item.rule_id, item.message] }.inspect}")
  end
end
