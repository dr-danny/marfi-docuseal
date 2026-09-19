# frozen_string_literal: true

class SubmissionRecipientsController < ApplicationController
  include MarfiAgreementsHelper

  load_and_authorize_resource :submission

  def index
    authorize!(:read, @submission)

    @submission = Submissions.preload_with_pages(@submission)

    unless @submission.completed_at?
      ActiveRecord::Associations::Preloader.new(
        records: [@submission],
        associations: [{ submitters: :start_form_submission_events }]
      ).call
    end

    render :index, layout: false
  end
end
