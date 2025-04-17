# frozen_string_literal: true

require "active_record_doctor/detectors/base"

module ActiveRecordDoctor
  module Detectors
    class IncorrectLengthValidation < Base # :nodoc:
      @description = "detect mismatches between database length limits and model length validations"
      @config = {
        ignore_models: {
          description: "models whose validators should not be checked",
          global: true
        },
        ignore_attributes: {
          description: "attributes, written as Model.attribute, whose validators should not be checked"
        }
      }

      private

      def message(model:, attribute:, table:, database_maximum:, model_maximum:)
        # rubocop:disable Layout/LineLength
        if database_maximum && model_maximum
          "the schema limits #{table}.#{attribute} to #{database_maximum} characters but the length validator on #{model}.#{attribute} enforces a maximum of #{model_maximum} characters - set both limits to the same value or remove both"
        elsif database_maximum && model_maximum.nil?
          "the schema limits #{table}.#{attribute} to #{database_maximum} characters but there's no length validator on #{model}.#{attribute} - remove the database limit or add the validator"
        elsif database_maximum.nil? && model_maximum
          "the length validator on #{model}.#{attribute} enforces a maximum of #{model_maximum} characters but there's no schema limit on #{table}.#{attribute} - remove the validator or the schema length limit"
        end
        # rubocop:enable Layout/LineLength
      end

      def detect
        each_model(except: config(:ignore_models), existing_tables_only: true) do |model|
          each_attribute(model, except: config(:ignore_attributes), type: [:string, :text]) do |column|
            table = model.table_name
            model_maximum = maximum_allowed_by_length_validation(model, column.name)
            database_maximum = column_limit(table, column)
            next if model_maximum == database_maximum
            next if column.limit && covered_by_inclusion_validation?(model, column.name, database_maximum)

            # Add violation only to the root model of STI.
            next if (model_maximum.nil? || database_maximum.nil?) && sti_subclass?(model)

            problem!(
              model: model.name,
              attribute: column.name,
              table: table,
              database_maximum: database_maximum,
              model_maximum: model_maximum
            )
          end
        end
      end

      def maximum_allowed_by_length_validation(model, column)
        length_validator = model.validators.find do |validator|
          validator.kind == :length &&
            validator.options.include?(:maximum) &&
            validator.attributes.map(&:to_s).include?(column)
        end
        length_validator ? length_validator.options[:maximum] : nil
      end

      def covered_by_inclusion_validation?(model, column, limit)
        inclusion_validator = model.validators.find do |validator|
          validator.kind == :inclusion &&
            validator.attributes.map(&:to_s).include?(column)
        end

        if inclusion_validator
          values = inclusion_validator.options[:in] || inclusion_validator.options[:within]
          if values.is_a?(Array) && values.all?(String)
            longest_value = values.max_by(&:size)
            longest_value.size <= limit
          end
        else
          false
        end
      end

      def column_limit(table, column)
        return column.limit if column.limit

        # Example: char_length(name::text) <= 64
        pattern = /(char_|character_)?length\(['"`]?#{column.name}(::text)?['"`]?\)\s*<=\s*(?<limit>\d+)/i

        check_constraints(table).each do |definition|
          match = definition.match(pattern)
          return match[:limit].to_i if match
        end

        nil
      end

      def sti_subclass?(model)
        model.columns_hash.include?(model.inheritance_column.to_s) &&
          model.base_class != model
      end
    end
  end
end
