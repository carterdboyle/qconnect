class Contact < ApplicationRecord
  belongs_to :user
  belongs_to :contact_user, class_name: "User"

  validates :user_id, uniqueness: { scope: :contact_user_id }
end