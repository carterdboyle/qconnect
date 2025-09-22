class User < ApplicationRecord
  has_one :user_key, dependent: :destroy
  validates :handle, presence: true, length: { in: 3..64 }
end
