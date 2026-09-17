# frozen_string_literal: true

require 'json'

module HexclavePilot
  # All pilot configuration is deliberately environment-only. This module does
  # not memoize values so an operator can disable the pilot immediately.
  class Config
    API_URL = 'https://api.hexclave.com/api/v1/users/me'
    ENABLED_VALUES = %w[1 true].freeze

    def self.enabled?
      ENABLED_VALUES.include?(ENV.fetch('HEXCLAVE_PILOT_ENABLED', '').downcase)
    end

    def self.available?
      enabled? && project_id.present? && publishable_client_key.present? && secret_server_key.present? && bindings.any?
    end

    def self.project_id
      ENV.fetch('HEXCLAVE_PILOT_PROJECT_ID', '').strip
    end

    def self.publishable_client_key
      ENV.fetch('HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY', '').strip
    end

    # Never call this from a view, helper, client-side config, or log statement.
    def self.secret_server_key
      ENV.fetch('HEXCLAVE_PILOT_SECRET_SERVER_KEY', '').strip
    end

    # Explicit subject-to-local-ID bindings prevent email/JIT linking.
    def self.bindings
      parsed = JSON.parse(ENV.fetch('HEXCLAVE_PILOT_BINDINGS_JSON', '{}'))
      return {} unless parsed.is_a?(Hash)

      parsed.each_with_object({}) do |(subject, local_id), result|
        next unless subject.is_a?(String) && subject.present?
        next unless local_id.to_s.match?(/\A[1-9]\d*\z/)

        result[subject] = local_id.to_i
      end
    rescue JSON::ParserError
      {}
    end
  end
end
