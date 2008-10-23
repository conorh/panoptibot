class AddMessageReceiverAndReference < ActiveRecord::Migration
  def self.up
    add_column :messages, :sent_to,   :string
    add_column :messages, :reference, :string
    add_index :messages, :sent_to
  end

  def self.down

  end
end
