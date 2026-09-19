# frozen_string_literal: true

class SubmissionsEditController < ApplicationController
  include MarfiAgreementsHelper

  load_and_authorize_resource :submission

  def create
    authorize!(:update, @submission)
    authorize!(:create, Submission)

    if @submission.completed_at?
      return redirect_to submission_path(@submission), alert: 'Completed agreements cannot be edited.'
    end

    if @submission.archived_at? || @submission.template&.archived_at? || @submission.expired?
      return redirect_to submission_path(@submission), alert: 'This agreement cannot be edited.'
    end

    new_submission = nil

    ActiveRecord::Base.transaction do
      new_submission = @submission.account.submissions.new(
        created_by_user: current_user,
        submitters_order: @submission.submitters_order,
        source: @submission.source,
        **@submission.slice(
          :template_fields,
          :account_id,
          :name,
          :template_id,
          :template_schema,
          :template_submitters,
          :preferences,
          :variables,
          :variables_schema,
          :expire_at
        )
      )

      new_submission.preferences = (@submission.preferences || {}).deep_dup
      new_submission.preferences.delete('voided')
      new_submission.preferences.delete('voided_at')
      new_submission.preferences.delete('voided_by_user_id')
      new_submission.preferences.delete('void_reason')
      new_submission.preferences.delete('replaced_by_id')
      new_submission.preferences['replaced_from_id'] = @submission.id
      new_submission.preferences['replaced_from_agreement_id'] = agreement_public_id(@submission)
      new_submission.preferences.delete('agreement_id') # force fresh ID

      @submission.submitters.order(:id).each do |submitter|
        new_submission.submitters.new(
          submitter.slice(:uuid, :email, :phone, :name, :preferences, :metadata, :account_id)
        )
      end

      new_submission.save!

      @submission.documents_attachments.each do |attachment|
        new_submission.documents_attachments.create!(uuid: attachment.uuid, blob_id: attachment.blob_id)
      end

      void_prefs = (@submission.preferences || {}).deep_dup
      void_prefs['voided'] = true
      void_prefs['voided_at'] = Time.current.iso8601
      void_prefs['voided_by_user_id'] = current_user.id
      void_prefs['void_reason'] = 'edited'
      void_prefs['replaced_by_id'] = new_submission.id
      void_prefs['replaced_by_agreement_id'] = agreement_public_id(new_submission)
      void_prefs['agreement_id'] ||= agreement_public_id(@submission)

      @submission.update!(archived_at: Time.current, preferences: void_prefs)
    end

    WebhookUrls.enqueue_events(@submission, 'submission.archived')
    WebhookUrls.enqueue_events(new_submission, 'submission.created')
    Submissions.send_signature_requests([new_submission])
    SearchEntries.enqueue_reindex([@submission, new_submission])

    redirect_to submission_path(new_submission),
                notice: "Agreement voided and reset. New ID #{agreement_public_id(new_submission)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to submission_path(@submission), alert: e.record.errors.full_messages.first || e.message
  end
end
