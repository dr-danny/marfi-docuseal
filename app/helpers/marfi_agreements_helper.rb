# frozen_string_literal: true

module MarfiAgreementsHelper
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
end
