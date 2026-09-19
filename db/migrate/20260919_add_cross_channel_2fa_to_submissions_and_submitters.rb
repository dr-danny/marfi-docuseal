# frozen_string_literal: true

class AddCrossChannel2faToSubmissionsAndSubmitters < ActiveRecord::Migration[7.0]
  def change
    add_column :submissions, :cross_channel_2fa_enabled, :boolean, default: true, null: false
    add_column :submitters, :invitation_channel, :string, limit: 10 # 'email' | 'sms' | nil
    add_column :submitters, :sms_2fa_verified, :boolean, default: false, null: false

    add_index :submitters, [:id, :invitation_channel]
  end
end
