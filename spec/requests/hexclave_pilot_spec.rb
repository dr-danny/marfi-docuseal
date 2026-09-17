# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Hexclave pilot', type: :request do
  let(:token) { 'test-access-token' }
  let(:provider_subject) { 'provider-subject-1' }
  let(:user) { create(:user, email: 'pilot@example.test') }

  before do
    user
    RateLimit::STORE.delete_matched(/\Ahexclave-pilot-/)
  end

  around do |example|
    old_values = %w[
      HEXCLAVE_PILOT_ENABLED HEXCLAVE_PILOT_PROJECT_ID
      HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY HEXCLAVE_PILOT_SECRET_SERVER_KEY
      HEXCLAVE_PILOT_BINDINGS_JSON
    ].index_with { |key| ENV.fetch(key, nil) }
    ENV['HEXCLAVE_PILOT_ENABLED'] = 'true'
    ENV['HEXCLAVE_PILOT_PROJECT_ID'] = 'project-id'
    ENV['HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY'] = 'public-key'
    ENV['HEXCLAVE_PILOT_SECRET_SERVER_KEY'] = 'secret-server-key'
    ENV['HEXCLAVE_PILOT_BINDINGS_JSON'] = { provider_subject => user.id }.to_json
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

    expect { get hexclave_pilot_path }.to raise_error(ActionController::RoutingError)

    expect { post hexclave_pilot_session_path, headers: { Authorization: "Bearer #{token}" } }.to raise_error(ActionController::RoutingError)

    get new_user_session_path
    expect(response.body).not_to include('Use pilot sign-in')
  end

  it 'renders public configuration but never the server secret' do
    get hexclave_pilot_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project-id', 'public-key')
    expect(response.body).not_to include('secret-server-key')
    expect(response.body).to include('hexclave_pilot')
    expect(response.headers['Content-Security-Policy']).to include("connect-src 'self' https://api.hexclave.com")
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
  end

  it 'requires CSRF for token exchange' do
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    expect { post hexclave_pilot_session_path, headers: { Authorization: "Bearer #{token}" } }.to raise_error(ActionController::InvalidAuthenticityToken)
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

  it 'accepts a real CSRF token while rotating the authenticated session' do
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    stub_identity
    get hexclave_pilot_path
    csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    old_session_id = request.session.id.to_s

    post hexclave_pilot_session_path,
         headers: { Authorization: "Bearer #{token}", 'X-CSRF-Token' => csrf }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(request.session.id.to_s).not_to eq(old_session_id)
    expect(controller.current_user).to eq(user)
  ensure
    ActionController::Base.allow_forgery_protection = old
  end

  it 'throttles repeated exchanges before another provider request' do
    provider = stub_request(:get, HexclavePilot::Config::API_URL).to_return(status: 401, body: '{}')

    11.times { post hexclave_pilot_session_path, headers: { Authorization: "Bearer #{token}" } }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After']).to eq('60')
    expect(provider).to have_been_requested.times(10)
  end

  it 'filters pilot credential parameter names from logs' do
    filters = Rails.application.config.filter_parameters.grep(Regexp)
    expect(filters.any? { |filter| filter.match?('access_token') }).to be(true)
    expect(filters.any? { |filter| filter.match?('authorization') }).to be(true)
    expect(filters.any? { |filter| filter.match?('nonce') }).to be(true)
    expect(filters.any? { |filter| filter.match?('refresh_token') }).to be(true)
  end
end
