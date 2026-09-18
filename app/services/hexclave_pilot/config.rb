# frozen_string_literal: true

require 'json'

module HexclavePilot
  # All pilot configuration is deliberately environment-only. This module does
  # not memoize values so an operator can disable the pilot immediately.
  #
  # The staged Hexclave project ("MARFI Secure eSIGN staging") enforces
  # publishable-client-key access. This deployment never requests, stores, or
  # exposes the project secret server key: the server verifies client access
  # tokens with the publishable client key only.
  class Config
    API_ORIGIN = 'https://apigcp.hexclave.com'
    API_URL = "#{API_ORIGIN}/api/v1/users/me".freeze

    # Non-secret staging identifiers. The browser receives both anyway.
    STAGING_PROJECT_ID = 'a6098321-36cd-458a-bbd8-12366f698aac'
    TRUSTED_ORIGIN = 'https://secure.marfi.app'

    # Only existing MARFI identities may sign in through the pilot.
    ALLOWED_EMAIL_DOMAIN = 'marfi.io'

    ENABLED_VALUES = %w[1 true].freeze

    def self.enabled?
      ENABLED_VALUES.include?(ENV.fetch('HEXCLAVE_PILOT_ENABLED', '').downcase)
    end

    def self.available?
      enabled? && project_id.present? && publishable_client_key.present? && bindings.any?
    end

    def self.project_id
      ENV.fetch('HEXCLAVE_PILOT_PROJECT_ID', STAGING_PROJECT_ID).strip
    end

    def self.publishable_client_key
      ENV.fetch('HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY', '').strip
    end

    # Exact-domain check: only addresses whose single domain label sequence is
    # exactly marfi.io. Subdomains, lookalike suffixes, and alias domains fail.
    def self.marfi_email?(email)
      local, separator, domain = email.to_s.strip.downcase.rpartition('@')
      separator == '@' && local.present? && domain == ALLOWED_EMAIL_DOMAIN
    end

    # Explicit subject-to-local-ID bindings prevent email/JIT linking. Keys are
    # immutable provider subjects; email-shaped keys are rejected so the map can
    # never degrade into email-based linking.
    def self.bindings
      parsed = JSON.parse(ENV.fetch('HEXCLAVE_PILOT_BINDINGS_JSON', '{}'))
      return {} unless parsed.is_a?(Hash)

      parsed.each_with_object({}) do |(subject, local_id), result|
        next unless subject.is_a?(String) && subject.present?
        next if subject.include?('@')
        next unless local_id.to_s.match?(/\A[1-9]\d*\z/)

        result[subject] = local_id.to_i
      end
    rescue JSON::ParserError
      {}
    end
  end
end
