# frozen_string_literal: true

module ActiveRecordDoctor
  module Utils # :nodoc:
    class << self
      def postgresql?(connection = ActiveRecord::Base.connection)
        ["PostgreSQL", "PostGIS"].include?(connection.adapter_name)
      end

      def mysql?(connection = ActiveRecord::Base.connection)
        connection.adapter_name == "Mysql2"
      end

      def expression_indexes_unsupported?(connection = ActiveRecord::Base.connection)
        (ActiveRecord::VERSION::STRING < "5.0") ||
          # Active Record is unable to correctly parse expression indexes for MySQL.
          (mysql?(connection) && ActiveRecord::VERSION::STRING < "7.1")
      end

      def attributes_api_supported?
        ActiveRecord::VERSION::STRING >= "5.0"
      end
    end
  end
end
