class ChatReadsCursorCleanup < ActiveRecord::Migration[8.0]
  def change
    # Keep id, drop t_ms
    remove_column :chat_reads, :last_read_t_ms, :bigint, if_exists: true

    add_index :chat_reads, :last_read_message_id
    add_foreign_key :chat_reads, :messages,
                    column: :last_read_message_id,
                    on_delete: :nullify
  end
end
