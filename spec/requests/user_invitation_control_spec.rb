# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Self-hosted user invitation control', type: :request do
  let(:admin) { create(:user) }
  let(:attributes) do
    { first_name: 'Emergency', last_name: 'Admin', email: 'recovery@example.test',
      password: 'only-for-this-test-password', role: 'admin' }
  end

  before do
    allow(Docuseal).to receive(:multitenant?).and_return(false)
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_later!: true)
    allow(UserMailer).to receive(:invitation_email).and_return(delivery)
    sign_in admin
  end

  it 'preserves the default invitation behavior' do
    expect { post users_path, params: { user: attributes } }.to change(User, :count).by(1)
    expect(response).to redirect_to(settings_users_path)
    expect(UserMailer).to have_received(:invitation_email).once
  end

  it 'creates a password-based administrator without sending an invitation' do

    expect { post users_path, params: { user: attributes, send_invitation: '0' } }.to change(User, :count).by(1)

    recovery = User.find_by!(email: attributes[:email])
    expect(recovery.account_id).to eq(admin.account_id)
    expect(recovery.valid_password?(attributes[:password])).to be(true)
    expect(response).to redirect_to(settings_users_path)
    expect(flash[:notice]).to eq('User created. No invitation email was sent.')
    expect(UserMailer).not_to have_received(:invitation_email)
  end

  it 'refuses silent creation without an explicit password' do

    expect do
      post users_path, params: { user: attributes.except(:password), send_invitation: '0' }
    end.not_to change(User, :count)

    expect(UserMailer).not_to have_received(:invitation_email)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'does not silently restore an archived user with a different password' do
    create(:user, account: admin.account, email: attributes[:email], archived_at: Time.current)

    expect do
      post users_path, params: { user: attributes, send_invitation: '0' }
    end.not_to change(User, :count)

    expect(UserMailer).not_to have_received(:invitation_email)
    expect(response).to have_http_status(:unprocessable_content)
    expect(User.find_by!(email: attributes[:email]).archived_at).to be_present
  end

  it 'does not grant provisioning permission to a viewer' do
    sign_in create(:user, account: admin.account, role: User::VIEWER_ROLE)

    expect do
      post users_path, params: { user: attributes, send_invitation: '0' }
    end.not_to change(User, :count)

    expect(UserMailer).not_to have_received(:invitation_email)
  end
end
