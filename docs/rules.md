# Operation lint rules

Run `graphql-operation-lint rules` to see which presets enable each rule.

## GraphQL validation

Configure individual `spec/*` checks under `rules`. Checks marked as requiring a schema run when a schema is supplied.

| Rule | Requires a schema |
| --- | --- |
| `spec/executable-definitions` | No |
| `spec/fields-on-correct-type` | Yes |
| `spec/fragments-on-composite-type` | Yes |
| `spec/known-argument-names` | Yes |
| `spec/known-directives` | Yes |
| `spec/known-fragment-names` | No |
| `spec/known-operation-types` | Yes |
| `spec/known-type-names` | Yes |
| `spec/lone-anonymous-operation` | No |
| `spec/no-fragment-cycles` | No |
| `spec/no-undefined-variables` | Yes |
| `spec/no-unused-variables` | Yes |
| `spec/one-field-subscriptions` | Yes |
| `spec/one-of-input-objects` | Yes |
| `spec/other` | Yes |
| `spec/overlapping-fields-can-be-merged` | Yes |
| `spec/possible-fragment-spread` | Yes |
| `spec/provided-required-arguments` | Yes |
| `spec/scalar-leafs` | Yes |
| `spec/unique-argument-names` | Yes |
| `spec/unique-directives-per-location` | Yes |
| `spec/unique-input-field-names` | Yes |
| `spec/unique-variable-names` | Yes |
| `spec/value-literals-of-correct-type` | Yes |
| `spec/variables-are-input-types` | Yes |
| `spec/variables-in-allowed-position` | Yes |

## Project conventions

### `lone-executable-definition`

Executable definitions must be in separate files.

Default severity `warning`.

- `ignore`. Type `string_list`. Default `[]`.

### `match-document-filename`

Each document filename must reflect the name of its first definition.

Default severity `warning`.

- `style`. Type `enum`. Default `"as_is"`. Values `as_is`, `PascalCase`, `camelCase`, `kebab-case`, `snake_case`.
- `suffixes`. Type `hash`. Default `{}`.
- `check_fragments`. Type `boolean`. Default `true`.

### `max-aliases`

An operation must stay within the configured number of aliased selections.

Default severity `warning`.

- `max`. Type `integer`. Default `10`.

### `max-operations-per-file`

Each file must stay within the configured number of operations.

Default severity `warning`.

- `max`. Type `integer`. Default `1`.
- `count_fragments`. Type `boolean`. Default `false`.

### `max-root-fields`

An operation must stay within the configured number of root fields.

Default severity `warning`.

- `max`. Type `hash`. Default `{"query":10,"mutation":1,"subscription":1}`.

### `max-selections`

An operation must stay within the configured total number of field selections.

Default severity `warning`.

- `max`. Type `integer`. Default `500`.

### `naming-convention`

Operation, fragment, and variable names must follow the configured conventions.

Default severity `warning`.

- `operations`. Type `hash`. Default `{"style":"PascalCase"}`.
- `query`. Type `hash`. Default `{}`.
- `mutation`. Type `hash`. Default `{}`.
- `subscription`. Type `hash`. Default `{}`.
- `fragments`. Type `hash`. Default `{"style":"PascalCase"}`.
- `variables`. Type `hash`. Default `{"style":"camelCase"}`.
- `fragment_type_prefix`. Type `boolean`. Default `false`.

### `no-anonymous-operations`

Every operation must have a name.

Default severity `error`.

### `no-deprecated`

Report deprecated fields, arguments, and literal input fields and enum values. Values supplied in variables are unavailable to static validation.

Default severity `warning`.
This rule requires a schema.

- `include`. Type `string_list`. Default `["fields","arguments","input_fields","enum_values"]`.
- `ignore`. Type `coordinate_patterns`. Default `[]`.

### `no-duplicate-fields`

Avoid selecting a field twice in the same selection set with the same response key and arguments.

Default severity `warning`.

### `no-one-place-fragments`

A fragment spread only once can be inlined.

Default severity `warning`.

### `no-unused-fragments`

Every fragment must be reachable from an operation.

Default severity `warning`.

- `ignore`. Type `string_list`. Default `[]`.
- `ignore_paths`. Type `glob_list`. Default `[]`.

### `require-selections`

Select the configured fields on types that define them.

Default severity `warning`.
This rule requires a schema.

- `fields`. Type `string_list`. Default `["id"]`.
- `ignore_types`. Type `coordinate_patterns`. Default `[]`.

### `restricted-fields`

Limit the use of configured field, argument, and type coordinates.

Default severity `error`.
This rule requires a schema.

- `fields`. Type `array`. Default `[]`.

### `selection-set-depth`

An operation must stay within the configured field depth after expanding fragments.

Default severity `warning`.

- `max`. Type `integer`. Default `10`.
- `ignore`. Type `string_list`. Default `[]`.
- `count_introspection`. Type `boolean`. Default `false`.

### `unique-fragment-name`

Fragment names must be unique in the document set.

Default severity `error`.

### `unique-operation-name`

Operation names must be unique in the selected scope.

Default severity `error`.

- `scope`. Type `enum`. Default `"project"`. Values `project`, `directory`.
