module Types
  class DailyPriceType < Types::BaseObject
    field :id, ID, null: false
    field :trading_date, String, null: false
    field :open, Float, null: true
    field :high, Float, null: true
    field :low, Float, null: true
    field :close, Float, null: false
    field :adjusted_close, Float, null: true
    field :volume, Integer, null: true
    field :traded_value, Float, null: true

    def trading_date
      object.trading_date.iso8601
    end
  end
end
