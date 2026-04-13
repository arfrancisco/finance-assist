require "rails_helper"

RSpec.describe Disclosures::PseEdge::ListingParser do
  let(:html) do
    <<~HTML
      <html><body>
      <table id="tblResults">
        <tbody>
          <tr>
            <td>2024-01-15</td>
            <td>Ayala Land Inc</td>
            <td>Annual Report</td>
            <td><a href="/DisclosureView/ViewDisclosure/12345">2023 Annual Report</a></td>
          </tr>
          <tr>
            <td>2024-01-14</td>
            <td>BDO Unibank Inc</td>
            <td>Quarterly Report</td>
            <td><a href="/DisclosureView/ViewDisclosure/12344">Q3 2023 Report</a></td>
          </tr>
        </tbody>
      </table>
      </body></html>
    HTML
  end

  subject(:parser) { described_class.new(html) }

  describe "#parse" do
    it "returns an array of disclosure hashes" do
      result = parser.parse
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end

    it "extracts the source_id from the link" do
      result = parser.parse
      expect(result.first[:source_id]).to eq("12345")
    end

    it "extracts the disclosure date" do
      result = parser.parse
      expect(result.first[:disclosure_date]).to eq(Date.new(2024, 1, 15))
    end

    it "extracts the company name" do
      result = parser.parse
      expect(result.first[:company_name]).to eq("Ayala Land Inc")
    end

    it "builds a full detail_url" do
      result = parser.parse
      expect(result.first[:detail_url]).to start_with("https://")
    end

    it "returns empty array for HTML with no disclosures" do
      result = described_class.new("<html><body><p>No disclosures</p></body></html>").parse
      expect(result).to eq([])
    end
  end
end
