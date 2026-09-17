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
    expect(html.at_css('link[rel="icon"]')['href']).to eq('/favicon-32x32.png?v=marfi-20260917')
    expect(html.at_css('.marfi-portal-attribution a:first-child')['href']).to eq(Docuseal::GITHUB_URL)
    expect(html.at_css('.marfi-portal-attribution a:last-child')['href']).to eq(Docuseal::SOURCE_URL)
    expect(response.headers['X-Robots-Tag']).to include('noindex')
    expect(html.at_css('title').text.strip).to eq('MARFI Secure eSIGN')
    expect(html.at_css('link[rel="canonical"]')['href']).to eq(root_url)
    expect(html.at_css('meta[property="og:image"]')['content']).to include('/marfi-secure-esign-social.png')
    expect(html.at_css('meta[property="og:image:width"]')['content']).to eq('1200')
    expect(html.at_css('meta[name="twitter:card"]')['content']).to eq('summary_large_image')
    expect(html.at_css('.marfi-wireframe')).to be_present
    expect(html.css('.marfi-portal-signin').length).to eq(1)
    expect(html.at_css('.marfi-portal-main .marfi-portal-signin')).to be_nil
    expect(html.at_css('.marfi-portal-art img')).to be_nil
    expect(html.at_css('.marfi-portal-legal a:nth-child(1)')['href']).to eq('https://marfi.ai/legal/privacy/')
    expect(html.at_css('.marfi-portal-legal a:nth-child(2)')['href']).to eq('https://marfi.ai/legal/terms/')
    expect(html.at_css('.marfi-portal-legal a:nth-child(3)')['href']).to eq('https://trust.marfi.io/monitoring')
    expect(html.text).not_to include('Private document signing', '01 / Secure portal')
  end
  it 'serves a MARFI-branded install manifest' do
    get '/manifest.json'

    expect(response).to have_http_status(:ok)
    manifest = response.parsed_body
    expect(manifest['name']).to eq('MARFI Secure eSIGN')
    expect(manifest['theme_color']).to eq('#08090d')
    expect(manifest['icons'].pluck('sizes')).to eq(%w[192x192 512x512])
    expect(manifest['icons'].first['src']).to include('/marfi-icon-192.png')
  end
end
