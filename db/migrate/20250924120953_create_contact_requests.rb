class CreateContactRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_requests do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: true, foreign_key:  { to_table: :users }
      t.string :recipient_handle, null: false
      t.text  :note
      t.integer :status, null: false, default: 0 #0=pending, 1=accepted, 2=declined
      t.timestamps
    end
    add_index :contact_requests, [:recipient_handle, :status]
    add_index :contact_requests, [:recipient_id, :status]
    add_index :contact_requests, [:requester_id, :status]
  end
end
