# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Document visibility', type: :request do
  let(:account) { create(:account) }
  let(:folder) { create(:template_folder, account:) }
  let(:editor) { create(:user, account:, role: User::EDITOR_ROLE) }
  let(:colleague) { create(:user, account:, role: User::EDITOR_ROLE) }

  let(:own_template) { create(:template, account:, author: editor, folder:, name: 'Own NDA') }
  let(:other_template) { create(:template, account:, author: colleague, folder:, name: 'Payroll') }

  it 'forbids an editor from opening another users template' do
    sign_in editor

    get template_path(own_template)
    expect(response).to have_http_status(:ok)

    get template_path(other_template)
    expect(response).to redirect_to(root_path)
  end
end
