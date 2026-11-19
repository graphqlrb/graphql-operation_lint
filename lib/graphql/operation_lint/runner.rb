# frozen_string_literal: true

module GraphQL
  module OperationLint
    class Runner
      Context = Data.define(:index, :document_set, :config)
      ActiveRule = Data.define(:instance, :diagnostics, :exclude, :paths)
      CALLBACKS = {
        enter_operation: :on_operation,
        leave_operation: :leave_operation,
        enter_fragment_definition: :on_fragment,
        enter_field: :on_field,
        enter_argument: :on_argument,
        enter_input_object: :on_input_object,
        enter_input_object_field: :on_input_object_field,
        enter_enum_literal: :on_enum_literal,
        enter_variable_definition: :on_variable_definition,
        enter_directive: :on_directive,
        enter_fragment_spread: :on_fragment_spread,
        enter_inline_fragment: :on_inline_fragment
      }.freeze

      def initialize(config:, overrides:, documents: nil, schema: nil)
        @config = config
        @overrides = overrides
        @documents = documents
        @schema = schema
        @diagnostics = []
        @sources = []
        @stats = {}
        @failed = {}
      end

      def run
        @settings = Core::Config.load(@config, defaults: DEFAULTS, presets: PRESETS,
          overrides: @overrides, filename: CONFIG_FILE)
        validate_configuration
        Core::Config.require_extensions(@settings)
        @rules = configured_rules
        schema = load_schema
        return result if schema&.fatal?

        document_set = load_documents
        @stats = { documents: document_set.sources.size, operations: document_set.operations.size, fragments: document_set.fragments.size }
        @diagnostics.concat(specification_diagnostics(document_set, schema))
        @diagnostics.concat(convention_diagnostics(document_set, schema&.index))
        result
      rescue Core::ConfigError, SystemCallError => error
        fatal("core/config-error", error)
      rescue SystemStackError => error
        fatal("core/input-error", error)
      rescue StandardError => error
        fatal("core/internal-error", error, status: 3)
      end

      private

      def validate_configuration
        docs = @settings["documents"]
        Core::Config.unknown_keys(docs, DEFAULTS.fetch("documents").keys, "documents")
        %w[include exclude].each { |key| Core::Config.check_strings(docs[key], "documents.#{key}") }
        Core::Config.enum(docs["fragment_resolution"], %w[global same_file], "documents.fragment_resolution")

        schema = @settings["schema"]
        Core::Config.unknown_keys(schema, Core::Config::SCHEMA_KEYS, "schema")
        %w[prelude skip_checks].each { |key| Core::Config.check_strings(schema[key], "schema.#{key}") }

        validation = @settings["validation"]
        Core::Config.unknown_keys(validation, DEFAULTS.fetch("validation").keys, "validation")
        timeout = validation["timeout"]
        unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
          raise Core::ConfigError, "validation.timeout must be a positive number."
        end
        unless validation["max_errors"].is_a?(Integer) && validation["max_errors"].positive?
          raise Core::ConfigError, "validation.max_errors must be a positive integer."
        end
      end

      def configured_rules
        rules = OperationLint.rules
        unknown = (@settings.fetch("rules").keys + Array(@settings["only"]) + Array(@settings["except"])).uniq - rules.keys
        unless unknown.empty?
          checker = DidYouMean::SpellChecker.new(dictionary: rules.keys)
          name = unknown.first
          suggestions = checker.correct(name)
          hint = suggestions.empty? ? "" : " Did you mean #{suggestions.join(', ')}?"
          raise Core::ConfigError, "Unknown operation rule `#{name}`.#{hint}"
        end

        @settings.fetch("rules").each_with_object({}) do |(id, raw), configured|
          config = raw.is_a?(Hash) ? raw : { "severity" => raw }
          rule = rules.fetch(id)
          options = rule.resolve_options(config.fetch("options", {}))
          severity = config["severity"]
          next if severity == "off" || severity == false
          next if @settings["only"] && !@settings["only"].include?(id)
          next if Array(@settings["except"]).include?(id)

          severity = rule.default_severity if severity.nil? || severity == true
          configured[id] = [rule, severity, options, config.fetch("exclude", [])]
        end
      end

      def load_schema
        settings = @settings.fetch("schema")
        sources = @schema || settings.fetch("sources")
        return if sources.nil? || (sources.is_a?(Array) && sources.empty?)

        loaded = Core::SchemaLoader.load(sources, prelude: settings.fetch("prelude"),
          skip_checks: settings.fetch("skip_checks"), emit_generated_sdl: settings["emit_generated_sdl"],
          repository: @settings.dig("git", "repository"), locale: @settings.fetch("locale"))
        @diagnostics.concat(loaded.diagnostics)
        @sources.concat(loaded.sources)
        loaded
      end

      def load_documents
        settings = @settings.fetch("documents")
        source = @documents || Core::Documents::FileSource.new(include: settings.fetch("include"), exclude: settings.fetch("exclude"))
        set = Core::Documents::DocumentSet.new(source, fragment_resolution: settings.fetch("fragment_resolution"))
        if set.sources.empty? && set.diagnostics.empty?
          raise Core::InputError, "No GraphQL documents match the specified input."
        end

        @sources.concat(set.sources)
        set
      end

      def specification_diagnostics(document_set, schema)
        diagnostics = document_set.diagnostics.dup
        if schema
          validation = @settings.fetch("validation")
          diagnostics.concat(Core::OperationValidator.new(schema, timeout: validation.fetch("timeout"),
            max_errors: validation.fetch("max_errors")).validate(document_set))
        else
          skipped = @rules.count { |_id, (rule, *)| rule.requires_schema? }
          if skipped.positive?
            message = @settings["locale"] == "ja" ? "Schema が指定されていないため、#{skipped} 件のルールをスキップしました。" :
              "Skipped #{skipped} rules because no schema was supplied."
            diagnostics << Core::Diagnostic.new(rule_id: "operation/schema-less", severity: :info, message: message,
              data: { skipped_rules: skipped })
          end
        end

        diagnostics.filter_map do |diagnostic|
          next diagnostic unless diagnostic.rule_id.start_with?("spec/")

          config = @rules[diagnostic.rule_id]
          next unless config

          _, severity, _, exclusions = config
          next if excluded?(diagnostic, exclusions, exclusions.map { |pattern| Core::CoordinatePattern.new(pattern) })

          localize_spec(diagnostic, severity)
        end
      end

      def localize_spec(diagnostic, severity)
        text = translations.fetch(diagnostic.rule_id, {})
        values = diagnostic.data.transform_keys(&:to_s).merge(diagnostic.data.fetch(:extensions, {}))
        values["detail"] = diagnostic.message
        message = text.fetch("message", "%{detail}").gsub(/%\{([a-zA-Z0-9_]+)\}/) do
          value = values[Regexp.last_match(1)]
          value.is_a?(Array) ? value.join(" → ") : (value || diagnostic.message).to_s
        end
        Core::Diagnostic.new(rule_id: diagnostic.rule_id, severity: severity, message: message,
          suggestion: text["suggestion"] || diagnostic.suggestion, message_key: diagnostic.message_key,
          location: diagnostic.location, related: diagnostic.related, operations: diagnostic.operations,
          data: diagnostic.data, fingerprint: diagnostic.fingerprint, fatal: diagnostic.fatal)
      end

      def convention_diagnostics(set, index)
        context = Context.new(index: index, document_set: set, config: @settings)
        active = @rules.filter_map do |id, (rule, severity, options, exclusions)|
          next if id.start_with?("spec/") || (!index && rule.requires_schema?)

          buffer = []
          instance = rule.new(options: options, severity: severity, diagnostics: buffer, locale: @settings.fetch("locale"),
            translations: translations.fetch(id, {}))
          invoke(instance, :setup, context)
          ActiveRule.new(instance: instance, diagnostics: buffer, exclude: exclusions,
            paths: exclusions.map { |pattern| Core::CoordinatePattern.new(pattern) })
        end
        walk(active.map(&:instance), set, index)
        active.each do |item|
          method = item.instance.method(:finish)
          args = method.arity.zero? ? [] : [set]
          invoke(item.instance, :finish, *args)
        end
        active.flat_map { |item| item.diagnostics.reject { |diagnostic| excluded?(diagnostic, item.exclude, item.paths) } }
      end

      def walk(rules, set, index)
        walker = Core::TypedWalker.new(index, set)
        %i[definitions operations].each do |mode|
          active = rules.select { |rule| rule.class.walk.include?(mode) }
          handlers = CALLBACKS.to_h do |event, callback|
            [event, active.select { |rule| rule.respond_to?(callback) }]
          end
          if mode == :definitions
            active.select { |rule| rule.respond_to?(:on_document) }.each do |rule|
              set.documents.each { |document| invoke(rule, :on_document, document) }
            end
          end
          next unless handlers.values.any? { |group| !group.empty? }

          definitions = mode == :definitions ? set.documents.flat_map(&:definitions) : set.operations
          definitions.each do |definition|
            walker.walk(definition, expand_fragments: mode == :operations) do |event, info|
              handlers.fetch(event, []).each { |rule| invoke(rule, CALLBACKS.fetch(event), info) }
            end
          end
        end
      end

      def invoke(rule, callback, *args)
        return if @failed[rule]

        rule.public_send(callback, *args)
      rescue StandardError => error
        @failed[rule] = true
        warn error.full_message if @settings["debug"]
        @diagnostics << Core::Diagnostic.new(rule_id: "core/rule-error", severity: :error,
          message: "Rule `#{rule.class.id}` failed: #{error.message}",
          data: { rule: rule.class.id }, location: (args.first.location if args.first.respond_to?(:location)))
      end

      def translations
        @translations ||= Psych.safe_load_file(File.join(ROOT, "locales", "#{@settings.fetch('locale')}.yml"), aliases: false)
          .fetch("rules", {})
      end

      def excluded?(diagnostic, patterns, coordinates)
        coordinates.any? { |pattern| pattern.match?(diagnostic.coordinate) } ||
          (diagnostic.location&.path && patterns.any? do |pattern|
            File.fnmatch?(pattern, diagnostic.location.path, Core::Documents::FileSource::FLAGS)
          end)
      end

      def result
        Core::Result.new(diagnostics: @diagnostics, tool: NAME, version: VERSION,
          config: @settings, sources: @sources, stats: @stats)
      end

      def fatal(id, error, status: 2)
        warn error.full_message if @settings&.fetch("debug", false)
        diagnostic = Core::Diagnostic.new(rule_id: id, severity: :error, message: error.message, fatal: status == 2)
        Core::Result.new(diagnostics: [diagnostic], tool: NAME, version: VERSION, exit_status: status)
      end
    end
  end
end
