class CreateMessages < ActiveRecord::Migration
  def self.up
    create_table :messages do |t|
      t.column :user_id, :integer
      t.column :nick, :string
      t.column :im_userid, :string
      t.column :body, :text
      t.column :full_message, :text
      t.column :created_at, :datetime
    end
    
  end

  def self.down
    drop_table :messages
  end
end
