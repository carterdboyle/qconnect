class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.bigint :t_ms, null: false
      t.binary :nonce, null: false
      t.binary :ck, null: false
      t.binary :cm, null: false
      t.binary :sig, null: false
      t.timestamps
    end
    add_index :messages, :recipient_id
    add_index :messages, :sender_id
  end
end
