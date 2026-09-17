# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    account_scope = { account_id: user.account_id }

    case user.role
    when User::VIEWER_ROLE
      can :read, Template, account_scope
      can :read, TemplateFolder, account_scope
      can :read, TemplateSharing, template: account_scope
      can :read, Submission, account_scope
      can :read, Submitter, account_scope
      can :read, Account, id: user.account_id
    when User::EDITOR_ROLE
      can %i[read create update], Template, account_scope
      can :destroy, Template, account_scope
      can :manage, TemplateFolder, account_scope
      can :manage, TemplateSharing, template: account_scope
      can :manage, Submission, account_scope
      can :manage, Submitter, account_scope
      can :read, Account, id: user.account_id
    else
      can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
        Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
      end

      can :destroy, Template, account_scope
      can :manage, TemplateFolder, account_scope
      can :manage, TemplateSharing, template: account_scope
      can :manage, Submission, account_scope
      can :manage, Submitter, account_scope
      can :manage, User, account_scope
      can :manage, EncryptedConfig, account_scope
      can :manage, EncryptedUserConfig, user_id: user.id
      can :manage, AccountConfig, account_scope
      can :manage, UserConfig, user_id: user.id
      can :manage, Account, id: user.account_id
      can :manage, AccessToken, user_id: user.id
      can :manage, McpToken, user_id: user.id
      can :manage, WebhookUrl, account_scope

      can :manage, :mcp
    end
  end
end
