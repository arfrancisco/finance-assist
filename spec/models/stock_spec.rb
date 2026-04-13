require "rails_helper"

RSpec.describe Stock, type: :model do
  describe "validations" do
    it "is valid with a symbol" do
      expect(build(:stock)).to be_valid
    end

    it "requires a symbol" do
      expect(build(:stock, symbol: nil)).not_to be_valid
    end

    it "requires a unique symbol" do
      create(:stock, symbol: "ALI")
      expect(build(:stock, symbol: "ALI")).not_to be_valid
    end
  end

  describe "associations" do
    let(:stock) { create(:stock) }

    it "has many daily_prices" do
      price = create(:daily_price, stock: stock)
      expect(stock.daily_prices).to include(price)
    end

    it "destroys daily_prices when destroyed" do
      create(:daily_price, stock: stock)
      expect { stock.destroy }.to change(DailyPrice, :count).by(-1)
    end

    it "has many disclosures" do
      expect(stock).to respond_to(:disclosures)
    end

    it "has many predictions" do
      expect(stock).to respond_to(:predictions)
    end
  end

  describe ".active" do
    it "returns only active stocks" do
      active = create(:stock, is_active: true)
      create(:stock, is_active: false)
      expect(Stock.active).to contain_exactly(active)
    end
  end
end
