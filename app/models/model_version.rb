class ModelVersion < ApplicationRecord
  has_many :predictions, dependent: :restrict_with_error

  validates :version_name, presence: true, uniqueness: true
end
