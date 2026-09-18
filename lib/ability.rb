# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    case user.role
    when User::VIEWER_ROLE then configure_viewer(user)
    when User::EDITOR_ROLE then configure_editor(user)
    else configure_admin(user)
    end
  end

  private

  def account_scope(user)
    { account_id: user.account_id }
  end

  def configure_viewer(user)
    scope = account_scope(user)

    can :read, Template, Abilities::DocumentVisibility.granted_templates(user)
    can :read, TemplateFolder, scope
    can :read, TemplateSharing, template_id: TemplateAccess.where(user_id: user.id).select(:template_id)
    can :read, Submission, Abilities::DocumentVisibility.visible_submissions(user)
    can :read, Submitter, Abilities::DocumentVisibility.visible_submitters(user)
    can :read, Account, id: user.account_id
  end

  def configure_editor(user)
    scope = account_scope(user)
    own_templates = Abilities::DocumentVisibility.editable_templates(user)
    visible_templates = Abilities::DocumentVisibility.visible_templates(user)

    can :create, Template, scope
    can %i[read update destroy], Template, own_templates
    can :read, Template, visible_templates
    can :manage, TemplateFolder, scope
    can :manage, TemplateSharing, template: { author_id: user.id, account_id: user.account_id }
    can :create, Submission, scope
    can :manage, Submission, created_by_user_id: user.id, account_id: user.account_id
    can :read, Submission, Abilities::DocumentVisibility.visible_submissions(user, include_own: true)
    can :manage, Submitter, submission: { created_by_user_id: user.id, account_id: user.account_id }
    can :read, Submitter, Abilities::DocumentVisibility.visible_submitters(user, include_own: true)
    can :read, Account, id: user.account_id
  end

  def configure_admin(user)
    scope = account_scope(user)

    can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
    end

    can :destroy, Template, scope
    can :manage, TemplateFolder, scope
    can :manage, TemplateSharing, template: scope
    can :manage, Submission, scope
    can :manage, Submitter, scope
    can :manage, User, scope
    can :manage, EncryptedConfig, scope
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, AccountConfig, scope
    can :manage, UserConfig, user_id: user.id
    can :manage, Account, id: user.account_id
    can :manage, AccessToken, user_id: user.id
    can :manage, McpToken, user_id: user.id
    can :manage, WebhookUrl, scope

    can :manage, :mcp
  end
end
