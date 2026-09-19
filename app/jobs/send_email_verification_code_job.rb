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

    # Generate TOTP code using phone+slug key (to match SMS 2FA verification logic)
    value = [submitter.phone.downcase.strip, submitter.slug].join(':')
    code = EmailVerificationCodes.generate(value)

    # Send email with the TOTP code
    I18n.with_locale(locale || submitter.account.locale) do
      SubmitterMailer.with(code:).cross_channel_email_verification(submitter).deliver_later
    end

    SubmissionEvent.create!(submitter_id: submitter.id,
                            event_type: 'send_2fa_email',
                            data: { email: submitter.email })
  end
end
