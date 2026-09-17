# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MARFI landing page', type: :request do
  it 'shows the branded entry point with sign-in, attribution and corresponding source' do
    create(:user)

    get '/'

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('h1').text).to eq('SecureeSIGN')
    expect(html.at_css('.marfi-portal-header .marfi-portal-signin')['href']).to eq(new_user_session_path)
    expect(html.at_css('meta[name="robots"]')['content']).to include('noindex')
    expect(html.at_css('link[rel="icon"]')['href']).to eq('/marfi-logo.png')
    expect(html.at_css('.marfi-portal-attribution a:first-child')['href']).to eq(Docuseal::GITHUB_URL)
    expect(html.at_css('.marfi-portal-attribution a:last-child')['href']).to eq(Docuseal::SOURCE_URL)
    expect(html.at_css('.marfi-wireframe')).to be_present
    expect(html.css('.marfi-portal-signin').length).to eq(1)
    expect(html.at_css('.marfi-portal-main .marfi-portal-signin')).to be_nil
    expect(html.at_css('.marfi-portal-art img')).to be_nil
    expect(html.at_css('.marfi-portal-legal a:nth-child(1)')['href']).to eq('https://marfi.ai/legal/privacy/')
    expect(html.at_css('.marfi-portal-legal a:nth-child(2)')['href']).to eq('https://marfi.ai/legal/terms/')
    expect(html.at_css('.marfi-portal-legal a:nth-child(3)')['href']).to eq('https://trust.marfi.io/monitoring')
    expect(html.text).not_to include('Private document signing', '01 / Secure portal')
  end
end
