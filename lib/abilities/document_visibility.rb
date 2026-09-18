# frozen_string_literal: true

module Abilities
  module DocumentVisibility
    module_function

    def editable_templates(user)
      Template.where(account_id: user.account_id, author_id: user.id)
    end

    def visible_templates(user)
      Template.where(account_id: user.account_id).where(
        Template.arel_table[:author_id].eq(user.id).or(
          Template.arel_table[:id].in(template_access_ids(user))
        )
      )
    end

    def granted_templates(user)
      Template.where(account_id: user.account_id, id: TemplateAccess.where(user_id: user.id).select(:template_id))
    end

    def own_submissions(user)
      Submission.where(account_id: user.account_id, created_by_user_id: user.id)
    end

    def visible_submissions(user, include_own: false)
      own = Submission.arel_table[:created_by_user_id].eq(user.id)
      added = Submission.arel_table[:id].in(added_submission_ids(user))
      granted = Submission.arel_table[:template_id].in(template_access_ids(user))

      clause = added.or(granted)
      clause = own.or(clause) if include_own

      Submission.where(account_id: user.account_id).where(clause)
    end

    def visible_submitters(user, include_own: false)
      Submitter.where(submission_id: visible_submissions(user, include_own:).select(:id))
    end

    def template_access_ids(user)
      TemplateAccess.where(user_id: user.id).select(:template_id).arel
    end

    def added_submission_ids(user)
      Submitter.where('LOWER(email) = ?', user.email.to_s.downcase).select(:submission_id).arel
    end
  end
end
