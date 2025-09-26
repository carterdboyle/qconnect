class Conversation < ApplicationRecord
  has_many :messages, dependent: :destroy
  has_many :chat_reads, dependent: :destroy

  def self.between(u1_id, u2_id)
    a, b = [u1_id, u2_id].minmax
    key = "#{a}:#{b}"
    find_or_create_by!(key:, a_id: a, b_id: b)
  end

  def peer_for(user_id)
    user_id == a_id ? b_id : a_id
  end

  
end