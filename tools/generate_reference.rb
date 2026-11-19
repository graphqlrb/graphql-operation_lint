# frozen_string_literal: true

require "fileutils"
require "json"
require "graphql/operation_lint"

path = File.expand_path("../docs/rules.md", __dir__)
lines = ["# Operation lint rules", "",
  "Run `graphql-operation-lint rules` to see which presets enable each rule.", "",
  "## GraphQL validation", "",
  "Configure individual `spec/*` checks under `rules`. Checks marked as requiring a schema run when a schema is supplied.", "",
  "| Rule | Requires a schema |", "| --- | --- |"]

specification, conventions = GraphQL::OperationLint.rules.sort.partition { |id, _| id.start_with?("spec/") }
specification.each do |id, rule|
  lines << "| `#{id}` | #{rule.requires_schema? ? "Yes" : "No"} |"
end

lines.concat(["", "## Project conventions", ""])
conventions.each do |id, rule|
  lines.concat(["### `#{id}`", "", rule.description, "", "Default severity `#{rule.default_severity}`."])
  lines << "This rule requires a schema." if rule.requires_schema?
  lines << ""
  next if rule.options.empty?

  rule.options.each do |name, option|
    details = ["Type `#{option.fetch(:type)}`.", "Default `#{JSON.generate(option[:default])}`."]
    details << "Values #{option[:values].map { |value| "`#{value}`" }.join(", ")}." if option[:values]
    details << option[:description] if option[:description]
    lines << "- `#{name}`. #{details.join(" ")}"
  end
  lines << ""
end

content = lines.join("\n")
if ARGV.include?("--check")
  abort("docs/rules.md is outdated. Run bundle exec rake docs:generate.") unless
    File.file?(path) && File.read(path, encoding: "UTF-8").gsub("\r\n", "\n") == content
else
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content, encoding: "UTF-8")
end
