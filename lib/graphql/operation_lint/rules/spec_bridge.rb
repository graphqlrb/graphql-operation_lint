# frozen_string_literal: true

module GraphQL
  module OperationLint
    module Rules
      module SpecBridge
        RULES = Core::OperationValidator::RULE_IDS.to_h do |rule_id|
          name = rule_id.delete_prefix("spec/").tr("-", " ")
          rule = Class.new(Rule) do
            id rule_id
            category :specification
            description "GraphQL validation rule for #{name}."
            default_severity :error
            requires_schema true unless Core::OperationValidator::DOCUMENT_RULES.include?(rule_id)
          end
          [rule_id, rule]
        end.freeze
      end
    end
  end
end
