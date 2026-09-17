# frozen_string_literal: true

class HexclavePilotController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  prepend_before_action :require_available_pilot

  def show; end

  def create
    result = HexclavePilot::Authenticator.call(access_token: bearer_token)

    if result.status == :success
      sign_in(:user, result.user)
      request.session.options[:renew] = true
      return redirect_to root_path
    end

    # Do not leak subject, email, account, MFA, or provider-token state. Native
    # sign-in remains available at the ordinary Devise route.
    render json: { error: 'Pilot sign-in was not accepted. Use native sign-in.' }, status: :unauthorized
  end

  private

  def require_available_pilot
    raise ActionController::RoutingError, 'Not Found' unless HexclavePilot::Config.available?
  end

  def bearer_token
    header = request.authorization.to_s
    match = header.match(/\ABearer\s+([^\s]+)\z/i)
    match ? match[1] : ''
  end
end
