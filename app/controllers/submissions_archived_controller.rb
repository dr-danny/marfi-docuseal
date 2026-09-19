# frozen_string_literal: true

class SubmissionsArchivedController < ApplicationController
  include MarfiAgreementsHelper
  load_and_authorize_resource :submission, parent: false

  def index
    @submissions = @submissions.left_joins(:template)
    @submissions = @submissions.where.not(archived_at: nil)
                               .or(@submissions.where.not(templates: { archived_at: nil }))
                               .preload(:created_by_user, template_accesses: :user)

    @submissions = Submissions.search(current_user, @submissions, params[:q], search_template: true)
    @submissions = Submissions::Filter.call(@submissions, current_user, params)

    @submissions = @submissions.select_for_list.preload(submitters: :start_form_submission_events)

    template_scope = Template.select_for_list
    ActiveRecord::Associations::Preloader.new(records: @submissions,
                                              associations: :template,
                                              scope: template_scope).call

    ActiveRecord::Associations::Preloader.new(records: @submissions.filter_map(&:template),
                                              associations: :author).call

    sorted = sort_agreements_by_status_then_sent(@submissions.to_a)
    @pagy, @submissions = pagy(:offset, sorted)
  end
end
