class AddCryptoFieldsToContactRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :contact_requests, :t_ms, :bigint, null: false #requester's timestamp
    add_column :contact_requests, :nonce, :binary, null: false #requester's nonce (16B)
    add_column :contact_requests, :sig, :binary, null: false #requester's sig
    add_column :contact_requests, :requester_ps, :binary, null: false #cache PS of requester
    add_index :contact_requests, :recipient_handle
  end
end
