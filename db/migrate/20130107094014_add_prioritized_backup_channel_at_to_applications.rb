class AddPrioritizedBackupChannelAtToApplications < ActiveRecord::Migration
  def self.up
    add_column :applications, :prioritized_backup_channel_at, :timestamp
  end

  def self.down
    remove_column :applications, :prioritized_backup_channel_at
  end
end
