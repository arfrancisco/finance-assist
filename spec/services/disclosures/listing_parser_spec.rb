require "rails_helper"

RSpec.describe Disclosures::PseEdge::ListingParser do
  let(:html) do
    <<~HTML
      <html><body>
      <table class="list">
        <tbody>
          <tr>
            <td><a onclick="openPopup('abc123def456')" href="#">Ayala Land Inc: 2023 Annual Report</a></td>
            <td>Jan 15, 2024 09:00 AM</td>
            <td>Annual Report</td>
            <td>PSE Form 17-A</td>
          </tr>
          <tr>
            <td><a onclick="openPopup('bcd234efg567')" href="#">BDO Unibank Inc: Q3 2023 Report</a></td>
            <td>Jan 14, 2024 10:30 AM</td>
            <td>Quarterly Report</td>
            <td>PSE Form 17-Q</td>
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

    it "extracts the source_id from the openPopup onclick" do
      result = parser.parse
      expect(result.first[:source_id]).to eq("abc123def456")
    end

    it "extracts the disclosure date" do
      result = parser.parse
      expect(result.first[:disclosure_date]).to eq(Date.new(2024, 1, 15))
    end

    it "extracts the company name from the title prefix" do
      result = parser.parse
      expect(result.first[:company_name]).to eq("Ayala Land Inc")
    end

    it "extracts the disclosure title" do
      result = parser.parse
      expect(result.first[:title]).to eq("2023 Annual Report")
    end

    it "builds a full detail_url containing the source_id" do
      result = parser.parse
      expect(result.first[:detail_url]).to eq("https://edge.pse.com.ph/openDiscViewer.do?edge_no=abc123def456")
    end

    it "extracts the disclosure type" do
      result = parser.parse
      expect(result.first[:disclosure_type]).to eq("Annual Report")
    end

    it "returns empty array for HTML with no table.list" do
      result = described_class.new("<html><body><p>No disclosures</p></body></html>").parse
      expect(result).to eq([])
    end

    it "skips rows without an openPopup onclick" do
      html_no_popup = <<~HTML
        <html><body>
        <table class="list">
          <tbody>
            <tr><td><a href="#">No popup link</a></td><td>Jan 15, 2024 09:00 AM</td><td>Type</td><td></td></tr>
          </tbody>
        </table>
        </body></html>
      HTML
      result = described_class.new(html_no_popup).parse
      expect(result).to eq([])
    end
  end
end
