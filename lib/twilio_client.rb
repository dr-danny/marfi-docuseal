# frozen_string_literal: true

require 'base64'
require 'faraday'
require 'json'

module TwilioClient
  module_function

  def send_message!(account_sid:, auth_token:, from:, to:, body:, messaging_service_sid: nil, status_callback: nil)
    raise 'Twilio Account SID missing' if account_sid.blank?
    raise 'Twilio Auth Token missing' if auth_token.blank?
    raise 'Twilio From missing' if from.blank?
    raise 'Twilio To missing' if to.blank?
    raise 'Twilio body missing' if body.blank?

    conn = Faraday.new(url: 'https://api.twilio.com') do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    payload = {
      'To' => to,
      'Body' => body
    }

    if messaging_service_sid.present?
      payload['MessagingServiceSid'] = messaging_service_sid
    else
      payload['From'] = from
    end

    payload['StatusCallback'] = status_callback if status_callback.present?

    response = conn.post("/2010-04-01/Accounts/#{account_sid}/Messages.json") do |req|
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{account_sid}:#{auth_token}")}"
      req.body = payload
    end

    data =
      begin
        JSON.parse(response.body)
      rescue StandardError
        { 'raw' => response.body }
      end

    unless response.success?
      message = data['message'] || data['raw'] || "Twilio HTTP #{response.status}"
      raise message
    end

    data
  end
end
