# frozen_string_literal: true

module MarfiAgreementsHelper
  STATUS_SORT_RANK = {
    'awaiting' => 0,
    'sent' => 1,
    'opened' => 2,
    'declined' => 3,
    'expired' => 4,
    'completed' => 5
  }.freeze

  STATUS_BADGES = {
    'awaiting' => 'is-awaiting',
    'sent' => 'is-sent',
    'completed' => 'is-completed',
    'opened' => 'is-opened',
    'declined' => 'is-declined',
    'expired' => 'is-declined'
  }.freeze

  def agreement_access_users(submission)
    users = []
    users << submission.created_by_user if submission.created_by_user
    users << submission.template&.author if submission.template&.author

    accesses = submission.template_accesses.to_a
    if accesses.any? { |access| access.user_id == TemplateAccess::ADMIN_USER_ID }
      users.concat(account_admin_users)
    end

    accesses.each do |access|
      next if access.user_id == TemplateAccess::ADMIN_USER_ID

      users << access.user if access.user
    end

    users.compact.uniq(&:id)
  end

  def account_admin_users
    @account_admin_users ||= current_account.users.active.admins.to_a
  end

  def agreement_submitters(submission)
    template = submission.template
    submitters = (submission.template_submitters || template&.submitters || []).filter_map do |item|
      submission.submitters.find { |e| e.uuid == item['uuid'] }
    end
    submitters = submission.submitters.to_a if submitters.blank?
    submitters
  end

  def agreement_row_status(submission)
    submitters = agreement_submitters(submission)
    latest = submitters.select(&:completed_at?).max_by(&:completed_at) ||
             submitters.max_by { |s| s.status_event_at || s.created_at }

    if submission.expired? && !submission.completed_at?
      'expired'
    elsif submission.completed_at?
      'completed'
    else
      latest&.status || 'awaiting'
    end
  end

  def agreement_date_sent(submission)
    agreement_submitters(submission).filter_map(&:sent_at).min || submission.created_at
  end

  def agreement_last_activity(submission)
    submitters = agreement_submitters(submission)
    latest = submitters.select(&:completed_at?).max_by(&:completed_at) ||
             submitters.max_by { |s| s.status_event_at || s.created_at }
    latest&.status_event_at || submission.completed_at || submission.created_at
  end

  def agreement_author(submission)
    submission.created_by_user || submission.template&.author
  end

  def agreement_signable_submitter(submission)
    return if current_user.blank? || submission.archived_at? || submission.expired?
    return if submission.template&.archived_at?

    user_email = current_user.email.to_s.strip.downcase
    agreement_submitters(submission).find do |submitter|
      submitter.email.to_s.strip.downcase == user_email &&
        submitter.completed_at.blank? &&
        submitter.declined_at.blank? &&
        !submitter.viewer?
    end
  end

  def sort_agreements_by_status_then_sent(submissions)
    submissions.sort_by do |submission|
      status = agreement_row_status(submission)
      sent_at = agreement_date_sent(submission)
      [STATUS_SORT_RANK.fetch(status, 99), -sent_at.to_i, -submission.id]
    end
  end
end
