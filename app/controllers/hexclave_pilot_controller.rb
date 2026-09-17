# frozen_string_literal: true

class HexclavePilotController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  prepend_before_action :require_available_pilot
  before_action :set_pilot_headers
  before_action :limit_exchange, only: :create

  rescue_from RateLimit::LimitApproached, with: :rate_limited

  def show; end

  def create
    result = HexclavePilot::Authenticator.call(access_token: bearer_token)

    if result.status == :success
      reset_session
      sign_in(:user, result.user)
      request.session.options[:renew] = true
      return redirect_to root_path
    end

    # Do not leak subject, email, account, MFA, or provider-token state. Native
    # sign-in remains available at the ordinary Devise route.
    render json: { error: 'Pilot sign-in was not accepted. Use native sign-in.' }, status: :unauthorized
  end

  private

  def limit_exchange
    RateLimit.call("hexclave-pilot-ip-#{request.remote_ip}", limit: 10, ttl: 1.minute, enabled: true)
    RateLimit.call('hexclave-pilot-global', limit: 30, ttl: 1.minute, enabled: true)
  end

  def rate_limited
    response.headers['Retry-After'] = '60'
    render json: { error: 'Too many pilot attempts. Use native sign-in or retry later.' }, status: :too_many_requests
  end

  def set_pilot_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    request.content_security_policy&.connect_src(:self, 'https://api.hexclave.com')
  end

  def require_available_pilot
    raise ActionController::RoutingError, 'Not Found' unless HexclavePilot::Config.available?
  end

  def bearer_token
    header = request.authorization.to_s
    match = header.match(/\ABearer\s+([^\s]+)\z/i)
    match ? match[1] : ''
  end
end
