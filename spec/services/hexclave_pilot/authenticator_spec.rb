# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HexclavePilot::Authenticator do
  let(:token) { 'test-access-token' }
  let(:subject) { 'provider-subject-1' }
  let(:user) { create(:user, email: 'pilot@example.test') }

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

  def stub_identity(payload, status: 200)
    stub_request(:get, HexclavePilot::Config::API_URL)
      .to_return(status: status, body: payload.to_json)
  end

  def identity(overrides = {})
    { id: subject, primary_email: user.email, primary_email_verified: true }.merge(overrides)
  end

  it 'fails closed when disabled or misconfigured' do
    ENV['HEXCLAVE_PILOT_ENABLED'] = 'false'
    expect(described_class.call(access_token: token).status).to eq(:disabled)

    ENV['HEXCLAVE_PILOT_ENABLED'] = 'true'
    ENV.delete('HEXCLAVE_PILOT_SECRET_SERVER_KEY')
    expect(described_class.call(access_token: token).status).to eq(:disabled)
  end

  it 'rejects an invalid provider token and malformed provider response' do
    stub_identity({}, status: 401)
    expect(described_class.call(access_token: token).status).to eq(:invalid_token)

    stub_request(:get, HexclavePilot::Config::API_URL).to_return(status: 200, body: '{not json')
    expect(described_class.call(access_token: token).status).to eq(:invalid_token)

    stub_request(:get, HexclavePilot::Config::API_URL).to_timeout
    expect(described_class.call(access_token: token).status).to eq(:invalid_token)
  end

  it 'does not follow a provider redirect' do
    provider = stub_request(:get, HexclavePilot::Config::API_URL)
               .to_return(status: 302, headers: { 'Location' => 'https://attacker.example/collect' })

    expect(described_class.call(access_token: token).status).to eq(:invalid_token)
    expect(provider).to have_been_requested.once
  end

  it 'refuses oversized tokens without an outbound request' do
    expect(described_class.call(access_token: 'x' * 8193).status).to eq(:invalid_token)
    expect(WebMock).not_to have_requested(:get, HexclavePilot::Config::API_URL)
  end

  it 'does not queue concurrent provider calls' do
    described_class::PROVIDER_REQUEST_MUTEX.lock
    expect(described_class.call(access_token: token).status).to eq(:invalid_token)
    expect(WebMock).not_to have_requested(:get, HexclavePilot::Config::API_URL)
  ensure
    described_class::PROVIDER_REQUEST_MUTEX.unlock
  end

  it 'requires a verified provider email and exact local email match' do
    stub_identity(identity(primary_email_verified: false))
    result = described_class.call(access_token: token)
    expect(result.status).to eq(:email_verification_failed)
    expect(WebMock).to have_requested(:get, HexclavePilot::Config::API_URL).with(headers: hash_including('X-Hexclave-Project-Id' => 'project-id'))

    stub_identity(identity(primary_email: 'different@example.test'))
    expect(described_class.call(access_token: token).status).to eq(:email_mismatch)
  end

  it 'rejects an unknown provider subject without email-only linking' do
    stub_identity(identity(id: 'unbound-subject'))

    expect { @result = described_class.call(access_token: token) }.not_to change(User, :count)
    expect(@result.status).to eq(:unknown_subject)
  end

  it 'rejects archived local users and archived accounts' do
    user.update!(archived_at: Time.current)
    stub_identity(identity)
    expect(described_class.call(access_token: token).status).to eq(:ineligible_user)

    user.update!(archived_at: nil)
    user.account.update!(archived_at: Time.current)
    stub_identity(identity)
    expect(described_class.call(access_token: token).status).to eq(:ineligible_user)
  end

  it 'refuses provider sign-in for a native MFA user' do
    user.update!(otp_required_for_login: true)
    stub_identity(identity)

    expect(described_class.call(access_token: token).status).to eq(:native_mfa_required)
  end

  it 'returns only the explicitly bound, existing eligible user' do
    stub_identity(identity)

    expect { @result = described_class.call(access_token: token) }.not_to change(User, :count)
    expect(@result.status).to eq(:success)
    expect(@result.user).to eq(user)
  end
end
