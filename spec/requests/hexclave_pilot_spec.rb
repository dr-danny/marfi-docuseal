# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Hexclave pilot', type: :request do
  let(:token) { 'test-access-token' }
  let(:provider_subject) { 'provider-subject-1' }
  let(:user) { create(:user, email: 'pilot@marfi.io') }

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
    ENV['HEXCLAVE_PILOT_BINDINGS_JSON'] = { provider_subject => user.id }.to_json
    example.run
  ensure
    old_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def stub_identity
    stub_request(:get, HexclavePilot::Config::API_URL)
      .to_return(status: 200, body: {
        id: provider_subject,
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
    expect(response.body).not_to include('hexclave-pilot-github')
  end

  it 'renders passwordless methods on the branded native sign-in page' do
    ENV['HEXCLAVE_PILOT_SECRET_SERVER_KEY'] = 'canary-secret-server-key'

    get new_user_session_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.marfi-auth-page')).to be_present
    expect(html.at_css('#hexclave-pilot-email')).to be_present
    expect(html.at_css('#hexclave-pilot-send')).to be_present
    expect(html.at_css('#hexclave-pilot-github')).to be_present
    expect(html.at_css('#hexclave-pilot-passkey')).to be_present
    expect(html.at_css('.marfi-auth-password summary')&.text).to include('Use a password instead')
    expect(html.at_css('.marfi-auth-card details input[name="user[password]"]')).to be_present
    expect(html.at_css('.marfi-auth-card form')['action']).to eq(user_session_path)
    expect(response.headers['Content-Security-Policy']).to include(
      "connect-src 'self' #{HexclavePilot::Config::BROWSER_CONNECT_ORIGINS.join(' ')}"
    )
    expect(response.body).not_to include('canary-secret-server-key')
  end

  it 'defaults to the staging project and never renders any server secret' do
    ENV.delete('HEXCLAVE_PILOT_PROJECT_ID')
    ENV['HEXCLAVE_PILOT_SECRET_SERVER_KEY'] = 'canary-secret-server-key'

    get hexclave_pilot_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(HexclavePilot::Config::STAGING_PROJECT_ID, 'public-key')
    expect(response.body).not_to include('canary-secret-server-key')
    expect(response.body).not_to include('HEXCLAVE_PILOT_SECRET_SERVER_KEY')
  end

  it 'renders the passwordless entry points and the domain restriction, with no password method' do
    get hexclave_pilot_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css('#hexclave-pilot-send')).to be_present
    expect(html.at_css('#hexclave-pilot-github')).to be_present
    expect(html.at_css('#hexclave-pilot-passkey')).to be_present
    expect(html.at_css('#hexclave-pilot-link-verify')).to be_present
    expect(html.at_css('#hexclave-pilot')['data-allowed-domain']).to eq('marfi.io')
    expect(html.text).to include('@marfi.io')
    expect(html.css('#hexclave-pilot input[type="password"]')).to be_empty
    expect(response.body).not_to include('signInWithCredential', 'resetPassword', 'sendForgotPasswordEmail')
  end

  it 'hardens pilot response headers and allows the Hexclave browser origins' do
    get hexclave_pilot_path

    expect(response.headers['Content-Security-Policy']).to include(
      "connect-src 'self' #{HexclavePilot::Config::BROWSER_CONNECT_ORIGINS.join(' ')}"
    )
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

  it 'fails closed to the native fallback without leaking which check failed' do
    stub_request(:get, HexclavePilot::Config::API_URL)
      .to_return(status: 200, body: {
        id: 'unbound-subject',
        primary_email: 'attacker-controlled@marfi.io',
        primary_email_verified: true
      }.to_json)

    post hexclave_pilot_session_path, headers: { Authorization: "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq({ 'error' => 'Pilot sign-in was not accepted. Use native sign-in.' })
    expect(controller.current_user).to be_nil
  end

  it 'rejects a non-MARFI provider identity at the exchange boundary' do
    stub_request(:get, HexclavePilot::Config::API_URL)
      .to_return(status: 200, body: {
        id: provider_subject,
        primary_email: 'pilot@marfi.io.attacker.example',
        primary_email_verified: true
      }.to_json)

    post hexclave_pilot_session_path, headers: { Authorization: "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(controller.current_user).to be_nil
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
)
    expect(filters.any? { |filter| filter.match?('access_token') }).to be(true)
    expect(filters.any? { |filter| filter.match?('authorization') }).to be(true)
    expect(filters.any? { |filter| filter.match?('nonce') }).to be(true)
    expect(filters.any? { |filter| filter.match?('refresh_token') }).to be(true)
  end
end
