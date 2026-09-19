# frozen_string_literal: true

class SubmitFormSms2fasController < ApplicationController
  around_action :with_browser_locale

  skip_before_action :authenticate_user!
  skip_authorization_check

  before_action :load_submitter

  def create
    # Detect if this is cross-channel email 2FA (SMS-invited signers needing email verification)
    is_cross_channel_email = @submitter.invitation_channel == 'sms'

    rate_key = is_cross_channel_email ? "verify-email-code-#{@submitter.id}" : "verify-sms-2fa-code-#{@submitter.id}"
    RateLimit.call(rate_key, limit: 2, ttl: 45.seconds, enabled: true)

    value = [@submitter.phone.downcase.strip, @submitter.slug].join(':')

    if EmailVerificationCodes.verify(params[:one_time_code].to_s.gsub(/\D/, ''), value)
      if is_cross_channel_email
        event_name = 'email_verified'
        flag_name = :email_2fa_verified
        cookie_key = :email_2fa_slug
      else
        event_name = 'sms_verified'
        flag_name = :sms_2fa_verified
        cookie_key = :sms_2fa_slug
      end

      SubmissionEvents.create_with_tracking_data(@submitter, event_name, request, { phone: @submitter.phone })

      @submitter.update!(flag_name => true)

      cookies.encrypted[cookie_key] =
        { value: @submitter.slug, expires: Submitters::StartForm::COOKIES_TTL.from_now,
          **Submitters::StartForm::COOKIES_DEFAULTS }

      redirect_to submit_form_path(@submitter.slug)
    else
      redirect_to submit_form_path(@submitter.slug, status: :error), alert: I18n.t(:invalid_code)
    end
  rescue RateLimit::LimitApproached
    redirect_to submit_form_path(@submitter.slug, status: :error), alert: I18n.t(:too_many_attempts)
  end

  def update
    # Detect if this is cross-channel email 2FA (SMS-invited signers needing email verification)
    is_cross_channel_email = @submitter.invitation_channel == 'sms'

    if is_cross_channel_email
      event_type = 'send_2fa_email'
      rate_key = "send-email-code-#{@submitter.id}"
    else
      event_type = 'send_sms_verification_code'
      rate_key = "send-sms-code-#{@submitter.id}"
    end

    if @submitter.submission_events.where(event_type:).exists?(created_at: 15.seconds.ago..)
      return redirect_to submit_form_path(@submitter.slug, status: :error), alert: I18n.t(:rate_limit_exceeded)
    end

    RateLimit.call(rate_key, limit: 2, ttl: 45.seconds, enabled: true)

    if is_cross_channel_email
      SendEmailVerificationCodeJob.perform_async('submitter_id' => @submitter.id, 'locale' => I18n.locale.to_s)
    else
      SendSmsVerificationCodeJob.perform_async('submitter_id' => @submitter.id, 'locale' => I18n.locale.to_s)
    end

    redir_params = params[:resend] ? { alert: I18n.t(:code_has_been_resent) } : {}

    redirect_to submit_form_path(@submitter.slug, status: :sent), **redir_params
  rescue RateLimit::LimitApproached
    redirect_to submit_form_path(@submitter.slug, status: :error), alert: I18n.t(:too_many_attempts)
  end

  private

  def load_submitter
    @submitter = Submitter.find_by!(slug: params[:submitter_slug])
  end
end
