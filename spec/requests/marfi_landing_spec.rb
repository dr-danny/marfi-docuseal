# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MARFI landing page', type: :request do
  it 'shows the branded entry point with sign-in, attribution and corresponding source' do
    get '/'

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('h1').text).to eq('SecureeSIGN')
    expect(html.at_css('.marfi-portal-signin')['href']).to eq(new_user_session_path)
    expect(html.at_css('meta[name="robots"]')['content']).to include('noindex')
    expect(html.at_css('link[rel="icon"]')['href']).to eq('/marfi-logo.png')
    expect(html.css('.marfi-portal-footer a').map { |link| link['href'] })
      .to eq([Docuseal::GITHUB_URL, Docuseal::SOURCE_URL])
    expect(html.text).not_to include('Private document signing', '01 / Secure portal')
  end
end
