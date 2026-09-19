# frozen_string_literal: true

class SendSmsVerificationCodeJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])

    return if submitter.phone.blank?
    return if submitter.submission.archived_at?
    return if submitter.submission.expired?
    return unless MarfiSms.configured?(submitter.account)

    # Generate 6-digit OTP
    code = SecureRandom.random_bytes(3).unpack1('H*').to_i(16) % 1_000_000
    code_str = code.to_s.rjust(6, '0')

    # Store hashed code (same as email verification)
    value = [submitter.phone.downcase.strip, submitter.slug].join(':')
    EmailVerificationCodes.generate(code_str, value, expires_in: 15.minutes)

    # Send SMS
    body = I18n.t('sms_verification_code_is', code: code_str, locale: submitter.account.locale || I18n.default_locale)

    cfg = MarfiSms.configs_for(submitter.account)

    if cfg['test_mode'] == true
      Rails.logger.info("[SendSmsVerificationCodeJob] test_mode to=#{submitter.phone} code=#{code_str}")
      result = { 'sid' => "TEST#{SecureRandom.hex(8)}", 'status' => 'test_mode' }
    else
      result = TwilioClient.send_message!(
        account_sid: cfg['account_sid'],
        auth_token: cfg['auth_token'],
        from: cfg['from_phone'],
        to: submitter.phone,
        body:,
        messaging_service_sid: cfg['messaging_service_sid'],
        status_callback: cfg['status_callback_url']
      )
    end

    SubmissionEvents.create_with_tracking_data(submitter, 'send_sms_verification_code', nil, {
      'to' => submitter.phone,
      'sid' => result['sid'],
      'status' => result['status'],
      'provider' => 'twilio'
    })
  rescue StandardError => e
    Rollbar.error(e) if defined?(Rollbar)
    Rails.logger.error("[SendSmsVerificationCodeJob] submitter=#{params['submitter_id']} error=#{e.message}")
    raise
  end
end
