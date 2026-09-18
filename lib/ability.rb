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
    granted = scope.merge(template_accesses: { user_id: user.id })
    added = scope.merge(submitters: { email: user.email })

    can :read, Template, granted
    can :read, TemplateFolder, scope
    can :read, TemplateSharing, template: granted
    can :read, Submission, added
    can :read, Submission, granted
    can :read, Submitter, email: user.email
    can :read, Account, id: user.account_id
  end

  def configure_editor(user)
    scope = account_scope(user)
    own = { author_id: user.id, account_id: user.account_id }
    own_submissions = { created_by_user_id: user.id, account_id: user.account_id }
    granted = scope.merge(template_accesses: { user_id: user.id })
    added = scope.merge(submitters: { email: user.email })

    can :create, Template, scope
    can %i[update destroy], Template, own
    can :read, Template, own
    can :read, Template, granted
    can :manage, TemplateFolder, scope
    can :manage, TemplateSharing, template: own
    can :create, Submission, scope
    can %i[update destroy], Submission, own_submissions
    can :read, Submission, own_submissions
    can :read, Submission, added
    can :read, Submission, granted
    can :create, Submitter, scope
    can %i[update destroy], Submitter, submission: own_submissions
    can :read, Submitter, email: user.email
    can :read, Submitter, submission: own_submissions
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
