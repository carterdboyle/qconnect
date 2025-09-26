class TimeCursorForMessages < ActiveRecord::Migration[8.0]
  def change
    add_index :messages, [:conversation_id, :t_ms, :id]

    add_column :chat_reads, :last_read_t_ms, :bigint, default: 0, null: false
  end
end
