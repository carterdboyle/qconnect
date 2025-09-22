class UserKey < ApplicationRecord
  self.primary_key = :user_id
  belongs_to :user
  validates :ps, :pk, presence: true
end
