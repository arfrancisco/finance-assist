require "rails_helper"

RSpec.describe DailyPrice, type: :model do
  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:daily_price)).to be_valid
    end

    it "requires trading_date" do
      expect(build(:daily_price, trading_date: nil)).not_to be_valid
    end

    it "requires close" do
      expect(build(:daily_price, close: nil)).not_to be_valid
    end

    it "requires unique trading_date per stock" do
      price = create(:daily_price)
      expect(build(:daily_price, stock: price.stock, trading_date: price.trading_date)).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to a stock" do
      price = create(:daily_price)
      expect(price.stock).to be_a(Stock)
    end
  end
end
