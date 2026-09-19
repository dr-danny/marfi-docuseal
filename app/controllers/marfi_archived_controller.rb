# frozen_string_literal: true

class MarfiArchivedController < ApplicationController
  skip_authorization_check

  def index
    if params[:kind].to_s == 'templates'
      cookies.permanent[:dashboard_view] = 'templates'
      TemplatesArchivedController.dispatch(:index, request, response)
    else
      cookies.permanent[:dashboard_view] = 'submissions'
      SubmissionsArchivedController.dispatch(:index, request, response)
    end
  end
end
