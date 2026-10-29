class Company < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
end
