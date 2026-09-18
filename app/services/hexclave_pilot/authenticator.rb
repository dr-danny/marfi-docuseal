# frozen_string_literal: true

require 'digest'
require 'faraday'
require 'json'

module HexclavePilot
  # Exchanges a short-lived client access token for a verified provider identity
  # and then permits only an explicit, currently eligible local-user binding.
  #
  # Provider verification uses the project publishable client key with client
  # access type. The secret server key is never requested, stored, or sent.
  class Authenticator
    Result = Struct.new(:status, :user)
    PROVIDER_TIMEOUT_SECONDS = 10
    MAX_TOKEN_BYTES = 8192
    PROVIDER_REQUEST_MUTEX = Mutex.new

    def self.call(access_token:)
      new(access_token: access_token).call
    end

    def initialize(access_token:)
      @access_token = access_token.to_s
    end

    def call
      return Result.new(status: :disabled) unless Config.available?
      return Result.new(status: :invalid_token) if access_token.blank? || access_token.bytesize > MAX_TOKEN_BYTES

      identity = provider_identity
      return Result.new(status: :invalid_token) unless identity
      return Result.new(status: :outside_allowed_domain) unless Config.marfi_email?(identity[:email])
      return Result.new(status: :email_verification_failed) unless identity[:email_verified]

      local_user_id = Config.bindings[identity[:subject]]
      return Result.new(status: :unknown_subject) unless local_user_id

      # Lookup is by the operator-provided subject binding only. Do not create or
      # discover local users by email here.
      user = User.find_by(id: local_user_id)
      return Result.new(status: :unknown_subject) unless user
      return Result.new(status: :outside_allowed_domain) unless Config.marfi_email?(user.email)
      return Result.new(status: :email_mismatch) unless secure_email_match?(user.email, identity[:email])
      return Result.new(status: :ineligible_user) unless user.active_for_authentication?

      Result.new(status: :success, user: user)
    end

    private

    attr_reader :access_token

    def provider_identity
      acquired = PROVIDER_REQUEST_MUTEX.try_lock
      return unless acquired

      response = provider_connection.get do |request|
        request.headers['X-Hexclave-Access-Type'] = 'client'
        request.headers['X-Hexclave-Project-Id'] = Config.project_id
        request.headers['X-Hexclave-Publishable-Client-Key'] = Config.publishable_client_key
        request.headers['X-Hexclave-Access-Token'] = access_token
      end
      return unless response.status == 200

      normalize_identity(JSON.parse(response.body))
    rescue Faraday::Error, JSON::ParserError, TypeError
      # Fail closed. Tokens, headers and provider response bodies are never logged.
      nil
    ensure
      PROVIDER_REQUEST_MUTEX.unlock if acquired
    end

    def provider_connection
      Faraday.new(url: Config::API_URL) do |connection|
        connection.options.open_timeout = PROVIDER_TIMEOUT_SECONDS
        connection.options.timeout = PROVIDER_TIMEOUT_SECONDS
        connection.adapter Faraday.default_adapter
      end
    end

    def normalize_identity(payload)
      return unless payload.is_a?(Hash)

      subject = payload['id']
      email = payload['primary_email'] || payload['primaryEmail']
      verified = payload['primary_email_verified']
      verified = payload['primaryEmailVerified'] if verified.nil?
      return unless subject.is_a?(String) && subject.present?
      return unless email.is_a?(String) && email.present?
      return unless verified == true || verified == false

      { subject: subject, email: email.strip.downcase, email_verified: verified }
    end

    def secure_email_match?(local_email, provider_email)
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(local_email.to_s.strip.downcase),
        Digest::SHA256.hexdigest(provider_email.to_s.strip.downcase)
      )
    end
  end
end
