# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MARFI sign-in branding', type: :request do
  it 'preserves native credentials, recovery and privacy within the branded page' do
    create(:user)

    get new_user_session_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.marfi-auth-page')).to be_present
    expect(html.at_css('.marfi-auth-card input[name="user[email]"]')).to be_present
    expect(html.at_css('.marfi-auth-card input[name="user[password]"]')).to be_present
    expect(html.at_css('.marfi-auth-card form')['action']).to eq(user_session_path)
    expect(html.at_css('.marfi-auth-card a')['href']).to eq(new_user_password_path)
    expect(response.headers['X-Robots-Tag']).to include('noindex')
  end
end
