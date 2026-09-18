# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HexclavePilot::Authenticator do
  let(:token) { 'test-access-token' }
  let(:provider_subject) { 'provider-subject-1' }
  let(:user) { create(:user, email: 'pilot@marfi.io') }

  around do |example|
    old_values = %w[
      HEXCLAVE_PILOT_ENABLED HEXCLAVE_PILOT_PROJECT_ID
      HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY
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

  def stub_identity(payload, status: 200)
    stub_request(:get, HexclavePilot::Config::API_URL)
      .to_return(status: status, body: payload.to_json)
  end

  def identity(overrides = {})
    { id: provider_subject, primary_email: user.email, primary_email_verified: true }.merge(overrides)
  end

  it 'fails closed when disabled or misconfigured' do
    ENV['HEXCLAVE_PILOT_ENABLED'] = 'false'
    expect(described_class.call(access_token: token).status).to eq(:disabled)

    ENV['HEXCLAVE_PILOT_ENABLED'] = 'true'
    ENV.delete('HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY')
    expect(described_class.call(access_token: token).status).to eq(:disabled)
  end

  it 'verifies tokens with the publishable client key and never sends a server key' do
    ENV['HEXCLAVE_PILOT_SECRET_SERVER_KEY'] = 'canary-secret-server-key'
    provider = stub_request(:get, HexclavePilot::Config::API_URL)
               .with do |request|
                 request.headers['X-Hexclave-Access-Type'] == 'client' &&
                   request.headers['X-Hexclave-Project-Id'] == 'project-id' &&
                   request.headers['X-Hexclave-Publishable-Client-Key'] == 'public-key' &&
                   !request.headers.key?('X-Hexclave-Secret-Server-Key') &&
                   !request.headers.value?('canary-secret-server-key')
               end
               .to_return(status: 200, body: identity.to_json)

    expect(described_class.call(access_token: token).status).to eq(:success)
    expect(provider).to have_been_requested.once
  ensure
    ENV.delete('HEXCLAVE_PILOT_SECRET_SERVER_KEY')
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

  it 'rejects provider identities outside the exact @marfi.io domain' do
    [
      'pilot@marfi.io.attacker.example',
      'pilot@evilmarfi.io',
      'pilot@mail.marfi.io',
      'pilot@marfi-io.com',
      'pilot@marfi.io.',
      'pilot@example.test',
      'pilot.marfi.io@example.test',
      '@marfi.io',
      'pilot@'
    ].each do |address|
      stub_identity(identity(primary_email: address))
      expect(described_class.call(access_token: token).status)
        .to eq(:outside_allowed_domain), "expected #{address} to be rejected"
      expect(WebMock).to have_requested(:get, HexclavePilot::Config::API_URL).once
      WebMock.reset_executed_requests!
    end
  end

  it 'accepts a mixed-case @marfi.io identity after normalization' do
    stub_identity(identity(primary_email: '  Pilot@MARFI.IO  '))

    expect(described_class.call(access_token: token).status).to eq(:success)
  end

  it 'refuses a bound local user whose own email is outside @marfi.io' do
    outsider = create(:user, email: 'bound-outsider@example.test')
    ENV['HEXCLAVE_PILOT_BINDINGS_JSON'] = { provider_subject => outsider.id }.to_json
    stub_identity(identity(primary_email: outsider.email))

    expect(described_class.call(access_token: token).status).to eq(:outside_allowed_domain)
  end

  it 'ignores email-shaped binding keys so the map cannot degrade to email linking' do
    ENV['HEXCLAVE_PILOT_BINDINGS_JSON'] = { user.email => user.id }.to_json

    expect(HexclavePilot::Config.bindings).to eq({})
    expect(described_class.call(access_token: token).status).to eq(:disabled)
  end

  it 'requires a verified provider email and exact local email match' do
    stub_identity(identity(primary_email_verified: false))
    expect(described_class.call(access_token: token).status).to eq(:email_verification_failed)

    stub_identity(identity(primary_email: 'different@marfi.io'))
    expect(described_class.call(access_token: token).status).to eq(:email_mismatch)
  end

  it 'rejects an unknown provider subject without email-only linking' do
    stub_identity(identity(id: 'unbound-subject'))

    result = nil
    expect { result = described_class.call(access_token: token) }.not_to change(User, :count)
    expect(result.status).to eq(:unknown_subject)
  end

  it 'does not auto-link when the provider email matches a local user but the subject is unbound' do
    other = create(:user, email: 'teammate@marfi.io')
    stub_identity(identity(id: 'unbound-subject', primary_email: other.email))

    result = nil
    expect { result = described_class.call(access_token: token) }.not_to change(User, :count)
    expect(result.status).to eq(:unknown_subject)
    expect(result.user).to be_nil
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

  it 'keeps unbound native recovery accounts outside every provider path' do
    recovery = create(:user, email: 'recovery-admin@marfi.io')
    stub_identity(identity(primary_email: recovery.email, id: 'unbound-recovery-subject'))

    result = described_class.call(access_token: token)
    expect(result.status).to eq(:unknown_subject)
    expect(result.user).to be_nil
    expect(recovery.reload.current_sign_in_at).to be_nil
  end

  it 'returns only the explicitly bound, existing eligible user' do
    stub_identity(identity)

    result = nil
    expect { result = described_class.call(access_token: token) }.not_to change(User, :count)
    expect(result.status).to eq(:success)
    expect(result.user).to eq(user)
  end
end
