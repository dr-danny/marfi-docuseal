# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ability do
  let(:account) { create(:account) }
  let(:folder) { create(:template_folder, account:) }
  let(:admin) { create(:user, account:, role: User::ADMIN_ROLE) }
  let(:editor) { create(:user, account:, role: User::EDITOR_ROLE) }
  let(:viewer) { create(:user, account:, role: User::VIEWER_ROLE) }
  let(:colleague) { create(:user, account:, role: User::EDITOR_ROLE) }
  let(:own_template) { create(:template, account:, author: editor, folder:, name: 'Own NDA') }
  let(:other_template) { create(:template, account:, author: colleague, folder:, name: 'Payroll') }
  let(:granted_template) { create(:template, account:, author: colleague, folder:, name: 'Granted') }

  def ids_for(user, klass)
    klass.accessible_by(described_class.new(user)).pluck(:id)
  end

  before do
    own_template
    other_template
    create(:template_access, template: granted_template, user: editor)
    create(:template_access, template: granted_template, user: viewer)
  end

  it 'lets admins see every account template' do
    expect(ids_for(admin, Template)).to include(own_template.id, other_template.id, granted_template.id)
  end

  it 'lets editors see own and granted templates only' do
    ability = described_class.new(editor)

    expect(ids_for(editor, Template)).to contain_exactly(own_template.id, granted_template.id)
    expect(ability.can?(:create, Template.new(account:))).to be(true)
    expect(ability.can?(:update, own_template)).to be(true)
    expect(ability.can?(:update, other_template)).to be(false)
  end

  it 'lets viewers see only granted templates and not create' do
    ability = described_class.new(viewer)

    expect(ids_for(viewer, Template)).to contain_exactly(granted_template.id)
    expect(ability.can?(:create, Template.new(account:))).to be(false)
  end

  describe 'submissions' do
    let(:own_submission) { create(:submission, template: own_template, created_by_user: editor) }
    let(:other_submission) { create(:submission, template: other_template, created_by_user: colleague) }
    let(:added_submission) do
      create(:submission, :with_submitters, template: other_template, created_by_user: colleague).tap do |submission|
        submission.submitters.first.update!(email: editor.email)
      end
    end
    let(:viewer_added_submission) do
      create(:submission, :with_submitters, template: other_template, created_by_user: colleague).tap do |submission|
        submission.submitters.first.update!(email: viewer.email)
      end
    end

    before do
      own_submission
      other_submission
      added_submission
      viewer_added_submission
    end

    it 'lets admins see every submission' do
      expect(ids_for(admin, Submission)).to include(
        own_submission.id, other_submission.id, added_submission.id, viewer_added_submission.id
      )
    end

    it 'lets editors see own and added submissions' do
      expect(ids_for(editor, Submission)).to include(own_submission.id, added_submission.id)
      expect(ids_for(editor, Submission)).not_to include(other_submission.id, viewer_added_submission.id)
    end

    it 'lets viewers see only submissions they were added to' do
      ability = described_class.new(viewer)

      expect(ids_for(viewer, Submission)).to contain_exactly(viewer_added_submission.id)
      expect(ability.can?(:create, Submission.new(account_id: account.id))).to be(false)
    end
  end
end
