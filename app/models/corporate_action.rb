class CorporateAction < ApplicationRecord
  belongs_to :stock

  validates :action_type, presence: true

  TYPES = %w[dividend split rights_offering suspension resumption other].freeze
end
