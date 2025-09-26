class User < ApplicationRecord
  has_one :user_key, dependent: :destroy

  # Contacts (both directons)
  has_many :contacts, dependent: :destroy
  has_many :inverse_contacts, class_name: "Contact", foreign_key: :contact_user_id,
    dependent: :destroy

  # Contact requests (both directions)
  has_many :contact_requests_made, class_name: "ContactRequest", foreign_key: :requester_id, dependent: :destroy
  has_many :contact_requests_received, class_name: "ContactRequest", foreign_key: :recipient_id, dependent: :destroy

  # Conversations user can be on either end
  has_many :conversations_as_a, class_name: "Conversation", foreign_key: :a_id, dependent: :destroy
  has_many :conversations_as_b, class_name: "Conversation", foreign_key: :b_id, dependent: :destroy

  def conversations
    Conversation.where("a_id = ? OR b_id = ?", id, id)
  end

  validates :handle, presence: true, length: { in: 3..64 }
end
