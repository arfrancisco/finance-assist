require "rails_helper"

RSpec.describe MarketData::Providers::EodhdClient do
  let(:client) { described_class.new(api_key: "test-api-key") }

  describe "#fetch_symbols", vcr: { cassette_name: "eodhd/symbols_pse" } do
    it "returns an array of symbol hashes" do
      result = client.fetch_symbols
      expect(result).to be_an(Array)
      expect(result.first).to include(:Code).or include("Code")
    end

    it "increments the call count" do
      expect { client.fetch_symbols }.to change(client, :call_count).by(1)
    end
  end

  describe "#fetch_eod_prices", vcr: { cassette_name: "eodhd/eod_prices_ali" } do
    it "returns price data with expected keys" do
      result = client.fetch_eod_prices(symbol: "ALI", from: "2024-01-01", to: "2024-01-31")
      expect(result).to be_an(Array)
      if result.any?
        row = result.first
        expect(row).to include(:date).or include("date")
        expect(row).to include(:close).or include("close")
      end
    end
  end

  describe "#fetch_eod_prices with 429 rate limit", vcr: { cassette_name: "eodhd/rate_limit_429" } do
    it "retries and raises on repeated failure" do
      expect {
        client.fetch_eod_prices(symbol: "ALI", from: "2024-01-01", to: "2024-01-31")
      }.to raise_error(Faraday::Error)
    end
  end

  describe "#fetch_eod_prices with 404", vcr: { cassette_name: "eodhd/not_found_404" } do
    it "raises a Faraday::ResourceNotFound error" do
      expect {
        client.fetch_eod_prices(symbol: "UNKNOWN", from: "2024-01-01", to: "2024-01-31")
      }.to raise_error(Faraday::ResourceNotFound)
    end
  end
end
