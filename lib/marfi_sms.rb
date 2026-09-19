# frozen_string_literal: true

module MarfiSms
  DEFAULT_INVITATION_BODY = <<~SMS.rstrip
    Hi {submitter.name}

    Your MARFI document is ready to be signed, please access it here:
    {submitter.link}

    Reply STOP to unsubscribe or HELP for help.
  SMS

  module_function

  def default_invitation_body
    DEFAULT_INVITATION_BODY
  end

  def configs_for(account)
    EncryptedConfig.find_by(account:, key: EncryptedConfig::SMS_CONFIGS_KEY)&.value
  end

  def configured?(account)
    cfg = configs_for(account)
    return false if cfg.blank?

    cfg['account_sid'].present? && cfg['auth_token'].present? && cfg['from_phone'].present?
  end

  def invitation_body_for(account)
    cfg = configs_for(account) || {}
    cfg['default_body'].presence || default_invitation_body
  end

  def send_invitation!(submitter)
    raise 'SMS is not configured' unless configured?(submitter.account)
    raise 'Recipient phone is required' if submitter.phone.blank?

    cfg = configs_for(submitter.account)
    body = ReplaceEmailVariables.call(
      invitation_body_for(submitter.account),
      submitter:,
      tracking_event_type: 'click_sms'
    )

    if cfg['test_mode'] == true
      Rails.logger.info("[MarfiSms] test_mode skip to=#{submitter.phone} body=#{body.truncate(200)}")
      return { 'sid' => "TEST#{SecureRandom.hex(8)}", 'status' => 'test_mode', 'to' => submitter.phone }
    end

    TwilioClient.send_message!(
      account_sid: cfg['account_sid'],
      auth_token: cfg['auth_token'],
      from: cfg['from_phone'],
      to: submitter.phone,
      body:,
      messaging_service_sid: cfg['messaging_service_sid'],
      status_callback: cfg['status_callback_url']
    )
  end
end
