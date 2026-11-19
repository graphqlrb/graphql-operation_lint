# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "graphql/operation_lint"

class OperationLintCLITest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  EXECUTABLE = File.join(ROOT, "exe/graphql-operation-lint")

  def test_cli_discovers_config_and_renders_two_formats
    with_project do |directory|
      File.write(File.join(directory, ".graphql-operation-lint.yml"), <<~YAML)
        version: 1
        schema:
          sources: [schema.graphql]
        documents:
          include: ['operations/**/*.gql']
      YAML
      stdout, stderr, status = cli(directory, "check", "--format", "json", "--format", "sarif:result.sarif")
      assert_equal 1, status.exitstatus, stderr
      assert_equal ["spec/fields-on-correct-type"], JSON.parse(stdout).fetch("diagnostics").map { |item| item.fetch("rule") }
      assert_equal "2.1.0", JSON.parse(File.read(File.join(directory, "result.sarif"))).fetch("version")
    end
  end

  def test_cli_can_check_positions_and_use_same_file_fragment_resolution
    with_project do |directory|
      File.write(File.join(directory, "operations/query.gql"), "query GetName { ...Parts }")
      File.write(File.join(directory, "operations/fragment.gql"), "fragment Parts on Query { name }")
      stdout, stderr, status = cli(directory, "operations/*.gql", "--format", "json")
      assert_equal 0, status.exitstatus, stderr
      assert_equal ["operation/schema-less"], JSON.parse(stdout).fetch("diagnostics").map { |item| item.fetch("rule") }

      File.write(File.join(directory, ".graphql-operation-lint.yml"), <<~YAML)
        version: 1
        documents:
          fragment_resolution: same_file
      YAML
      stdout, stderr, status = cli(directory, "--documents", "operations/*.gql", "--format", "json")
      assert_equal 1, status.exitstatus, stderr
      assert_includes JSON.parse(stdout).fetch("diagnostics").map { |item| item.fetch("rule") }, "spec/known-fragment-names"
    end
  end

  def test_cli_honors_suppression_and_baseline
    with_project do |directory|
      File.write(File.join(directory, ".graphql-operation-lint.yml"), <<~YAML)
        version: 1
        schema:
          sources: [schema.graphql]
        documents:
          include: ['operations/**/*.gql']
        baseline: baseline.json
      YAML
      _, stderr, status = cli(directory, "baseline", "update")
      assert_equal 0, status.exitstatus, stderr
      stdout, stderr, status = cli(directory, "check", "--format", "json")
      assert_equal 0, status.exitstatus, stderr
      assert_equal 1, JSON.parse(stdout).fetch("summary").fetch("suppressed").fetch("baseline")

      File.write(File.join(directory, "operations/query.gql"), <<~GRAPHQL)
        query GetName {
          # graphql-lint-disable-next-line spec/fields-on-correct-type -- planned change
          missing
        }
      GRAPHQL
      stdout, stderr, status = cli(directory, "check", "--no-baseline", "--format", "json")
      assert_equal 0, status.exitstatus, stderr
      assert_equal 1, JSON.parse(stdout).fetch("summary").fetch("suppressed").fetch("comment")
    end
  end

  def test_invalid_schema_and_invalid_document_have_different_exit_statuses
    with_project do |directory|
      File.write(File.join(directory, "operations/query.gql"), "query Broken {")
      _, stderr, status = cli(directory, "check", "operations/*.gql", "--schema", "schema.graphql")
      assert_equal 1, status.exitstatus, stderr
      File.write(File.join(directory, "schema.graphql"), "type Query {")
      stdout, stderr, status = cli(directory, "check", "operations/*.gql", "--schema", "schema.graphql", "--format", "json")
      assert_equal 2, status.exitstatus, stderr
      assert JSON.parse(stdout).fetch("diagnostics").first.fetch("fatal")
    end
  end

  private

  def with_project
    Dir.mktmpdir("operation-lint") do |directory|
      Dir.mkdir(File.join(directory, "operations"))
      File.write(File.join(directory, "schema.graphql"), "type Query { name: String }")
      File.write(File.join(directory, "operations/query.gql"), "query GetName { missing }")
      yield directory
    end
  end

  def cli(directory, *args)
    Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), EXECUTABLE, *args, chdir: directory)
  end
end
