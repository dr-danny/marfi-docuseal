# frozen_string_literal: true

module Submitters
  module AuthorizedForForm
    Unauthorized = Class.new(StandardError)

    module_function

    def call(submitter, current_user, request)
      pass_email_2fa?(submitter, request) && pass_link_2fa?(submitter, current_user, request) &&
        pass_cross_channel_2fa?(submitter, current_user, request)
    end

    def pass_email_2fa?(submitter, request)
      return false unless submitter

      return true if submitter.submission.template&.preferences&.dig('require_email_2fa') != true &&
                     submitter.preferences['require_email_2fa'] != true
      return true if request.cookie_jar.encrypted[:email_2fa_slug] == submitter.slug

      token = request.params[:two_factor_token].presence || request.headers['x-two-factor-token'].presence

      return true if token.present? &&
                     Submitter.signed_id_verifier.verified(token, purpose: :email_two_factor) == submitter.slug

      false
    end

    def pass_link_2fa?(submitter, current_user, request)
      return false unless submitter

      return true if submitter.submission.source != 'link'
      return true unless submitter.submission.template&.preferences&.dig('shared_link_2fa') == true
      return true if request.cookie_jar.encrypted[:email_2fa_slug] == submitter.slug
      return true if submitter.email == current_user&.email && current_user&.account_id == submitter.account_id

      if (token = request.params[:two_factor_token].presence || request.headers['x-two-factor-token'].presence)
        link_2fa_key = [submitter.email.downcase.squish, submitter.submission.template.slug].join(':')

        return true if Submitter.signed_id_verifier.verified(token, purpose: :email_two_factor) == link_2fa_key
      end

      false
    end

    def pass_cross_channel_sms_2fa?(submitter, current_user, request)
      return false unless submitter

      # Skip if disabled on this submission
      return true if submitter.submission.cross_channel_2fa_enabled == false

      # Skip if already authenticated (internal staff or existing user)
      return true if submitter.email == current_user&.email && current_user&.account_id == submitter.account_id

      # Skip if MARFI staff (@marfi.io)
      return true if submitter.email.present? && submitter.email.downcase.end_with?('@marfi.io')

      # If no invitation channel set, skip for now (backward compat)
      return true if submitter.invitation_channel.blank?

      # Only handle email-invited signers needing SMS verification
      return true unless submitter.invitation_channel == 'email'

      # Must verify via SMS
      return true if request.cookie_jar.encrypted[:sms_2fa_slug] == submitter.slug
      return true if submitter.sms_2fa_verified?

      false
    end

    def pass_cross_channel_2fa?(submitter, current_user, request)
      return false unless submitter

      # Skip if disabled on this submission
      return true if submitter.submission.cross_channel_2fa_enabled == false

      # Skip if already authenticated (internal staff or existing user)
      return true if submitter.email == current_user&.email && current_user&.account_id == submitter.account_id

      # Skip if MARFI staff (@marfi.io)
      return true if submitter.email.present? && submitter.email.downcase.end_with?('@marfi.io')

      # If no invitation channel set, skip for now (backward compat)
      return true if submitter.invitation_channel.blank?

      # Cross-channel verification required
      case submitter.invitation_channel
      when 'email'
        # Invited via email → must verify via SMS
        return true if request.cookie_jar.encrypted[:sms_2fa_slug] == submitter.slug
        return true if submitter.sms_2fa_verified?
        false
      when 'sms'
        # Invited via SMS → must verify via email
        return true if request.cookie_jar.encrypted[:email_2fa_slug] == submitter.slug
        # Email verification also sets the submitter's email_2fa_verified preference
        false
      else
        # Unknown channel, skip for safety
        true
      end
    end
  end
end
