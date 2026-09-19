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

  it 'brands the signed-in portal chrome like MARFI Secure eSIGN' do
    user = create(:user)
    sign_in user

    get root_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.marfi-app')).to be_present
    expect(html.at_css('.marfi-app-header')).to be_present
    expect(html.at_css('.marfi-app-product')&.text).to include('Secure eSIGN')
    expect(html.at_css('.marfi-app-header')&.text).not_to include('DocuSeal OSS')
    expect(html.at_css('.marfi-app-footer')).to be_nil
    expect(response.body).not_to include('Forked from')
    expect(response.body).not_to include('Secure eSign')
  end

  it 'hides Console, Ask AI, and Test mode from signed-in chrome' do
    user = create(:user, role: 'superadmin')
    sign_in user

    get settings_profile_index_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    visible_text = html.text.gsub(/\s+/, ' ')
    dropdown = html.at_css('.dropdown-content')&.text.to_s
    settings_menu = html.at_css('#account_settings_menu')&.text.to_s

    expect(dropdown).to include('Settings')
    expect(dropdown).to include('Sign out')
    expect(dropdown).not_to include('Console')
    expect(dropdown).not_to include('Ask AI')
    expect(dropdown).not_to include('Test mode')
    expect(settings_menu).not_to include('Console')
    expect(settings_menu).not_to include('Test mode')
    expect(visible_text).not_to include('Ask AI')
    expect(visible_text).not_to include('Test mode')
    expect(response.body).not_to include(Docuseal::CONSOLE_URL)
    expect(response.body).not_to include(Docuseal::CHATGPT_URL)
  end

  it 'puts dashboard search, upload, create, and workspace tabs in the navbar' do
    user = create(:user)
    sign_in user

    get root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    header = html.at_css('.marfi-app-header')
    expect(header).to be_present
    expect(header.at_css('#search')).to be_present
    expect(header.at_css('#templates_upload_button')).to be_present
    expect(header.at_css('#templates_archived_button')).to be_present
    expect(header.at_css('#templates_submissions_toggle')).to be_present
    expect(header.text).to include('Templates')
    expect(header.text).to include('Submissions')
    expect(header.text).to include('Create')
    expect(header.text).to include('Settings')
    expect(html.at_css('dashboard-dropzone #templates_submissions_toggle')).to be_nil
    expect(html.at_css('dashboard-dropzone #search')).to be_nil
  end

  it 'hides dashboard navbar actions on settings screens' do
    user = create(:user)
    sign_in user

    get settings_profile_index_path

    expect(response).to have_http_status(:ok)
    header = Nokogiri::HTML(response.body).at_css('.marfi-app-header')
    expect(header.at_css('#search')).to be_nil
    expect(header.at_css('#templates_upload_button')).to be_nil
    expect(header.at_css('#templates_submissions_toggle')).to be_nil
    expect(header.text).to include('Settings')
  end

  it 'keeps the AGPL corresponding-source notice in transactional email attribution' do
    html = ApplicationController.render(partial: 'shared/email_attribution')

    expect(html).to include(Docuseal::SOURCE_URL)
  end
end
