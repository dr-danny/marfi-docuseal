# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Document visibility', type: :request do
  let(:account) { create(:account) }
  let(:folder) { create(:template_folder, account:) }
  let(:editor) { create(:user, account:, role: User::EDITOR_ROLE) }
  let(:colleague) { create(:user, account:, role: User::EDITOR_ROLE) }

  before do
    create(:template, account:, author: editor, folder:, name: 'Own NDA')
    create(:template, account:, author: colleague, folder:, name: 'Payroll')
  end

  it 'hides another users templates from the editor dashboard' do
    sign_in editor
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Own NDA')
    expect(response.body).not_to include('Payroll')
  end
end
