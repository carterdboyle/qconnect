class CreateCoreSchema < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :handle, null: false
      t.timestamps
    end
    add_index :users, :handle, unique: true

    create_table :user_keys, id: false do |t|
      t.integer :user_id, null: false, primary_key: true
      t.binary  :ps, null: false # Dilithium public key
      t.binary :pk, null: false #Kyber512 public key
      t.timestamps
    end

    create_table :used_nonces do |t|
      t.binary :signer_ps, null: false
      t.binary :nonce, null: false
      t.datetime :seen_at, null: false, default: -> { "CURRENT_TIMESTAMP"}
    end

    add_index :used_nonces, [:signer_ps, :nonce], unique: true
  end
end
