# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MARFI UI removals', type: :request do
  it 'shows no language selector on any native authentication page' do
    create(:user)

    [new_user_session_path, new_user_password_path].each do |path|
      get path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.css('select[name="lang"]')).to be_empty
      expect(html.css('input[name="lang"]')).to be_empty
      expect(response.body).not_to include('language_')
    end
  end

  it 'keeps the DocuSeal OSS attribution without the Source link in the auth footer' do
    create(:user)

    get new_user_session_path

    html = Nokogiri::HTML(response.body)
    attribution = html.at_css('.marfi-auth-attribution')
    expect(attribution).to be_present
    expect(attribution.css('a').length).to eq(1)
    expect(attribution.at_css('a')['href']).to eq(Docuseal::GITHUB_URL)
    expect(attribution.text).not_to include('Source')
    expect(html.css('a').map { |link| link.text.strip }).not_to include('Source')
  end

  it 'shows no language selector in account settings while keeping the timezone control' do
    user = create(:user)
    sign_in user

    get settings_account_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css('select[name*="locale"]')).to be_empty
    expect(html.css('select[name="lang"]')).to be_empty
    expect(html.at_css('select[name*="timezone"]')).to be_present
  end

  it 'keeps the AGPL corresponding-source notice in transactional email attribution' do
    html = ApplicationController.render(partial: 'shared/email_attribution')

    expect(html).to include(Docuseal::SOURCE_URL)
  end
end
