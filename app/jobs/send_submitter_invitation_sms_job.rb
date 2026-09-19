# frozen_string_literal: true

class SendSubmitterInvitationSmsJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])

    return if submitter.completed_at?
    return if submitter.declined_at?
    return if submitter.submission.archived_at?
    return if submitter.submission.expired?
    return if submitter.template&.archived_at?
    return if submitter.phone.blank?
    return if submitter.preferences['send_sms'] == false
    return unless MarfiSms.configured?(submitter.account)

    result = MarfiSms.send_invitation!(submitter)

    SubmissionEvent.create!(
      submitter:,
      event_type: 'send_sms',
      data: {
        'to' => submitter.phone,
        'sid' => result['sid'],
        'status' => result['status'],
        'provider' => 'twilio'
      }.compact
    )

    submitter.sent_at ||= Time.current
    submitter.save!
  rescue StandardError => e
    Rollbar.error(e) if defined?(Rollbar)
    Rails.logger.error("[SendSubmitterInvitationSmsJob] submitter=#{params['submitter_id']} error=#{e.message}")
    raise
  end
end
