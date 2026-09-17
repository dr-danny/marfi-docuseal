# frozen_string_literal: true

class SessionsController < Devise::SessionsController
  before_action :configure_permitted_parameters
  after_action :renew_session_after_native_login, only: :create

  around_action :with_browser_locale

  def create
    email = sign_in_params[:email].to_s.downcase

    if Docuseal.multitenant? && !User.exists?(email:)
      Rollbar.warning('Sign in new user') if defined?(Rollbar)

      return redirect_to new_registration_path(sign_up: true, user: sign_in_params.slice(:email)),
                         notice: I18n.t('create_a_new_account')
    end

    if User.exists?(email:, otp_required_for_login: true) && sign_in_params[:otp_attempt].blank?
      return render :otp, locals: { resource: User.new(sign_in_params) }, status: :unprocessable_content
    end

    super
  end

  private

  def after_sign_in_path_for(...)
    if params[:redir].present?
      return console_redirect_index_path(redir: params[:redir]) if params[:redir].starts_with?(Docuseal::CONSOLE_URL)

      return params[:redir]
    end

    super
  end

  # Rails rotates the session id on commit while retaining Warden's newly signed-in user.
  # It only runs for Devise's successful native password/MFA redirect response.
  def renew_session_after_native_login
    request.session.options[:renew] = true if response.redirect? && user_signed_in?
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [:otp_attempt])
  end

  def set_flash_message(key, kind, options = {})
    return if key == :alert && kind == 'already_authenticated'

    super
  end
end
