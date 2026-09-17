# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Hexclave pilot', type: :request do
  let(:token) { 'test-access-token' }
  let(:subject) { 'provider-subject-1' }
  let(:user) { create(:user, email: 'pilot@example.test') }

  before { user }

  around do |example|
    old_values = %w[
      HEXCLAVE_PILOT_ENABLED HEXCLAVE_PILOT_PROJECT_ID
      HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY HEXCLAVE_PILOT_SECRET_SERVER_KEY
      HEXCLAVE_PILOT_BINDINGS_JSON
    ].to_h { |key| [key, ENV[key]] }
    ENV['HEXCLAVE_PILOT_ENABLED'] = 'true'
    ENV['HEXCLAVE_PILOT_PROJECT_ID'] = 'project-id'
    ENV['HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY'] = 'public-key'
    ENV['HEXCLAVE_PILOT_SECRET_SERVER_KEY'] = 'secret-server-key'
    ENV['HEXCLAVE_PILOT_BINDINGS_JSON'] = { subject => user.id }.to_json
    example.run
  ensure
    old_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def stub_identity
    stub_request(:get, HexclavePilot::Config::API_URL)
      .to_return(status: 200, body: {
        id: subject,
        primary_email: user.email,
        primary_email_verified: true
      }.to_json)
  end

  it 'does not expose the page or link when disabled' do
    ENV['HEXCLAVE_PILOT_ENABLED'] = 'false'

    get hexclave_pilot_path
    expect(response).to have_http_status(:not_found)

    get new_user_session_path
    expect(response.body).not_to include('Use pilot sign-in')
  end

  it 'renders public configuration but never the server secret' do
    get hexclave_pilot_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project-id', 'public-key')
    expect(response.body).not_to include('secret-server-key')
    expect(response.body).to include('hexclave_pilot')
  end

  it 'requires CSRF for token exchange' do
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post hexclave_pilot_session_path, headers: { Authorization: "Bearer #{token}" }
    expect(response).to have_http_status(:unprocessable_content)
  ensure
    ActionController::Base.allow_forgery_protection = old
  end

  it 'signs in the existing bound user with a fixed same-origin destination' do
    stub_identity

    post hexclave_pilot_session_path,
         params: { redir: 'https://attacker.example' },
         headers: { Authorization: "Bearer #{token}" }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it 'filters pilot credential parameter names from logs' do
    expect(Rails.application.config.filter_parameters).to include(:access_token, :authorization, :nonce, :refresh_token)
  end
end
