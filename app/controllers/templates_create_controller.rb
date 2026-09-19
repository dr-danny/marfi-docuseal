# frozen_string_literal: true

class TemplatesCreateController < ApplicationController
  def show
    authorize! :create, Template

    @template = current_account.templates.new
  end
end
