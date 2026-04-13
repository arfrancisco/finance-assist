require "rails_helper"

RSpec.describe MarketData::Importers::EodPricesImporter do
  let(:provider) { instance_double(MarketData::Providers::EodhdClient) }
  let(:importer) { described_class.new(provider: provider) }
  let(:stock) { create(:stock, symbol: "ALI") }

  let(:raw_prices) do
    [
      { date: "2024-01-02", open: 27.50, high: 28.00, low: 27.20, close: 27.80, adjusted_close: 27.80, volume: 5_200_000 },
      { date: "2024-01-03", open: 27.80, high: 28.10, low: 27.60, close: 27.95, adjusted_close: 27.95, volume: 4_800_000 }
    ]
  end

  before do
    stock
    allow(provider).to receive(:fetch_eod_prices).and_return(raw_prices)
  end

  describe "#call" do
    it "inserts daily price rows" do
      expect { importer.call(symbol: "ALI", from: "2024-01-01") }.to change(DailyPrice, :count).by(2)
    end

    it "returns the number of upserted rows" do
      expect(importer.call(symbol: "ALI", from: "2024-01-01")).to eq(2)
    end

    it "is idempotent (re-running does not duplicate rows)" do
      importer.call(symbol: "ALI", from: "2024-01-01")
      expect { importer.call(symbol: "ALI", from: "2024-01-01") }.not_to change(DailyPrice, :count)
    end

    it "returns 0 for unknown symbol" do
      expect(importer.call(symbol: "UNKNOWN", from: "2024-01-01")).to eq(0)
    end
  end
end
