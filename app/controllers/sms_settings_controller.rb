# frozen_string_literal: true

class SmsSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, except: :index

  def index; end

  def create
    attrs = sms_configs
    existing = (@encrypted_config.value.is_a?(Hash) ? @encrypted_config.value.deep_dup : {})

    value = existing.merge(attrs[:value] || {})
    value['provider'] = 'twilio'
    value['account_sid'] = value['account_sid'].to_s.strip
    value['from_phone'] = value['from_phone'].to_s.gsub(/[^0-9+]/, '')
    value['messaging_service_sid'] = value['messaging_service_sid'].to_s.strip.presence
    value['status_callback_url'] = value['status_callback_url'].to_s.strip.presence
    value['test_mode'] = value['test_mode'].in?([true, '1', 'true', 'on'])

    auth_token = attrs.dig(:value, 'auth_token').to_s.strip
    if auth_token.present? && auth_token != '*************'
      value['auth_token'] = auth_token
    elsif existing['auth_token'].present?
      value['auth_token'] = existing['auth_token']
    end

    default_body = attrs.dig(:value, 'default_body').to_s
    value['default_body'] = default_body if attrs[:value]&.key?('default_body')

    if value['account_sid'].blank? || value['from_phone'].blank? || value['auth_token'].blank?
      flash.now[:alert] = 'Twilio Account SID, Auth Token, and From phone are required.'
      @encrypted_config.value = value
      return render :index, status: :unprocessable_content
    end

    @encrypted_config.value = value

    if @encrypted_config.save
      redirect_to settings_sms_configs_path, notice: I18n.t('changes_have_been_saved')
    else
      flash.now[:alert] = @encrypted_config.errors.full_messages.first || 'Unable to save SMS settings.'
      render :index, status: :unprocessable_content
    end
  rescue StandardError => e
    flash.now[:alert] = e.message
    render :index, status: :unprocessable_content
  end

  def destroy
    @encrypted_config.destroy!
    redirect_to settings_sms_configs_path, notice: 'SMS settings have been reset.'
  end

  private

  def load_encrypted_config
    @encrypted_config =
      EncryptedConfig.find_or_initialize_by(account: current_account, key: EncryptedConfig::SMS_CONFIGS_KEY)
  end

  def sms_configs
    params.require(:encrypted_config).permit(
      value: %i[account_sid auth_token from_phone messaging_service_sid status_callback_url test_mode default_body]
    )
  end
end
