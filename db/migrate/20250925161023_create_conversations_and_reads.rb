class CreateConversationsAndReads < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.string :key, null: false # something like "min_id:max_id" for pairwise uniqueness
      t.integer :a_id, null: false
      t.integer :b_id, null: false
      t.timestamps
    end
    add_index :conversations, :key, unique: true
    add_index :conversations, :a_id
    add_index :conversations, :b_id

    add_column :messages, :conversation_id, :bigint, null: false
    add_index :messages, :conversation_id

    create_table :chat_reads do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.bigint :last_read_message_id, null: true
      t.datetime :updated_at, null: false, default: -> {"CURRENT_TIMESTAMP"}
    end
    add_index :chat_reads, [:conversation_id, :user_id], unique: true
  end
end
