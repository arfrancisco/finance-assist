require "rails_helper"

RSpec.describe MarketData::Importers::SymbolsImporter do
  let(:provider) { instance_double(MarketData::Providers::EodhdClient) }
  let(:importer) { described_class.new(provider: provider) }

  describe "#call" do
    let(:raw_symbols) do
      [
        { Code: "ALI", Name: "Ayala Land Inc" },
        { Code: "BDO", Name: "BDO Unibank Inc" }
      ]
    end

    before { allow(provider).to receive(:fetch_symbols).and_return(raw_symbols) }

    it "creates stock records" do
      expect { importer.call }.to change(Stock, :count).by(2)
    end

    it "returns the number of upserted records" do
      expect(importer.call).to eq(2)
    end

    it "is idempotent (re-running does not create duplicates)" do
      importer.call
      expect { importer.call }.not_to change(Stock, :count)
    end

    it "upserts symbol in uppercase" do
      importer.call
      expect(Stock.find_by(symbol: "ALI")).to be_present
    end
  end
end
