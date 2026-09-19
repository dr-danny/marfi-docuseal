# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Completed document archive', type: :request do
  let(:user) { create(:user) }
  let(:template) { create(:template, account: user.account, author: user) }
  let(:incomplete) { create(:submission, :with_submitters, template:, created_by_user: user) }
  let(:completed) do
    create(:submission, :with_submitters, template:, created_by_user: user, completed_at: Time.current)
  end

  before { sign_in user }

  it 'asks for confirmation and hides archive on completed documents' do
    incomplete
    completed

    get template_path(template)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    archive_button = html.at_css(%(form[action="#{submission_path(incomplete)}"] button))
    expect(archive_button).to be_present
    expect(archive_button['data-turbo-confirm']).to eq(I18n.t('are_you_sure_'))
    expect(archive_button['class']).to include('marfi-archive-action')
    expect(html.at_css(%(form[action="#{submission_path(completed)}"] button[title="#{I18n.t('archive')}"]))).to be_nil
  end

  it 'does not let an admin archive a completed document' do
    delete submission_path(completed)

    expect(completed.reload.archived_at).to be_nil
    expect(flash[:alert]).to eq(I18n.t('completed_documents_cannot_be_archived'))
  end

  it 'still archives an incomplete document' do
    delete submission_path(incomplete)

    expect(incomplete.reload.archived_at).to be_present
  end
end
