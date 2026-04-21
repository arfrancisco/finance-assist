require "rails_helper"

RSpec.describe MarketData::Importers::SymbolsImporter do
  let(:provider) { instance_double(MarketData::Providers::EodhdClient) }
  let(:sectors_csv) do
    path = Tempfile.new([ "pse_sectors", ".csv" ]).path
    File.write(path, <<~CSV)
      symbol,sector,industry
      # comment line, should be ignored
      ALI,Property,Property Developers
      BDO,Financial,Banks
      NOSECTOR,,
    CSV
    path
  end
  let(:importer) { described_class.new(provider: provider, sectors_csv_path: sectors_csv) }

  describe "#call" do
    let(:raw_symbols) do
      [
        { Code: "ALI", Name: "Ayala Land Inc" },
        { Code: "BDO", Name: "BDO Unibank Inc" },
        { Code: "NOSECTOR", Name: "No Sector Corp" }
      ]
    end

    before { allow(provider).to receive(:fetch_symbols).and_return(raw_symbols) }

    it "creates stock records" do
      expect { importer.call }.to change(Stock, :count).by(3)
    end

    it "returns the number of upserted records" do
      expect(importer.call).to eq(3)
    end

    it "is idempotent (re-running does not create duplicates)" do
      importer.call
      expect { importer.call }.not_to change(Stock, :count)
    end

    it "upserts symbol in uppercase" do
      importer.call
      expect(Stock.find_by(symbol: "ALI")).to be_present
    end

    it "overlays sector and industry from the CSV" do
      importer.call
      ali = Stock.find_by(symbol: "ALI")
      expect(ali.sector).to eq("Property")
      expect(ali.industry).to eq("Property Developers")
    end

    it "skips rows with a blank sector and leaves sector/industry untouched" do
      importer.call
      nos = Stock.find_by(symbol: "NOSECTOR")
      expect(nos.sector).to be_nil
      expect(nos.industry).to be_nil
    end

    it "ignores comment lines in the CSV" do
      expect { importer.call }.not_to raise_error
    end

    it "re-applying the overlay is idempotent" do
      importer.call
      Stock.find_by(symbol: "ALI").update!(sector: "Stale", industry: "Stale")
      importer.call
      ali = Stock.find_by(symbol: "ALI")
      expect(ali.sector).to eq("Property")
      expect(ali.industry).to eq("Property Developers")
    end

    context "when the sectors CSV is missing" do
      let(:importer) { described_class.new(provider: provider, sectors_csv_path: "/nonexistent/path.csv") }

      it "still imports symbols and logs a warning" do
        expect(Rails.logger).to receive(:warn).with(/Sector CSV not found/)
        expect { importer.call }.to change(Stock, :count).by(3)
      end
    end
  end
end
