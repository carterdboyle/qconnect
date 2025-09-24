class CreateContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :contact_user, null: false, foreign_key: { to_table: :users }
      t.string :alias
      t.timestamps
    end
    add_index :contacts, [ :user_id, :contact_user_id ], unique: true
  end
end
