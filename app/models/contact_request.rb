class ContactRequest < ApplicationRecord
  enum :status, { pending: 0, accepted: 1, declined: 2 }

  belongs_to :requester, class_name: "User"
  belongs_to :recipient, class_name: "User", optional: true

  validates :recipient_handle, presence: true
end