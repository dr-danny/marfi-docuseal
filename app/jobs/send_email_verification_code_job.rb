# frozen_string_literal: true

# For cross-channel 2FA: SMS-invited signers need email verification
# Uses phone as the verification key (same as SMS verification)

class SendEmailVerificationCodeJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])

    return if submitter.email.blank?
    return if submitter.submission.archived_at?
    return if submitter.submission.expired?

    locale = params['locale'].presence || submitter.account.locale

    # Generate code using phone as key (to match SMS 2FA verification logic)
    value = [submitter.phone.downcase.strip, submitter.slug].join(':')
    code = SecureRandom.random_bytes(3).unpack1('H*').to_i(16) % 1_000_000
    code_str = code.to_s.rjust(6, '0')
    EmailVerificationCodes.generate(code_str, value, expires_in: 15.minutes)

    # Send email with the code using the cross-channel mailer method
    I18n.with_locale(locale || submitter.account.locale) do
      SubmitterMailer.cross_channel_email_verification(submitter, code_str).deliver_later
    end

    SubmissionEvent.create!(submitter_id: submitter.id,
                            event_type: 'send_2fa_email',
                            data: { email: submitter.email })
  end
end
