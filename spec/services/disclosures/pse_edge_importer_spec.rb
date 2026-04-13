require "rails_helper"

RSpec.describe Disclosures::PseEdge::Importer do
  let(:fetcher) { instance_double(Disclosures::PseEdge::Fetcher) }
  let(:downloader) { instance_double(Disclosures::PseEdge::AttachmentDownloader) }
  let(:importer) { described_class.new(fetcher: fetcher, downloader: downloader, pages: 1) }

  let(:listing_html) do
    <<~HTML
      <html><body>
      <table id="tblResults">
        <tbody>
          <tr>
            <td>2024-01-15</td>
            <td>Ayala Land Inc</td>
            <td>Annual Report</td>
            <td><a href="/DisclosureView/ViewDisclosure/99001">2023 Annual Report</a></td>
          </tr>
        </tbody>
      </table>
      </body></html>
    HTML
  end

  let(:detail_html) do
    <<~HTML
      <html><body>
      <div class="disclosure-content">
        <p>Annual report content here.</p>
        <a href="/downloads/report.pdf">Download</a>
      </div>
      </body></html>
    HTML
  end

  before do
    create(:stock, symbol: "ALI", company_name: "Ayala Land Inc")
    allow(fetcher).to receive(:fetch_listing).and_return(listing_html)
    allow(fetcher).to receive(:fetch_detail).and_return(detail_html)
    allow(downloader).to receive(:call).and_return(1)
  end

  describe "#call" do
    it "creates a disclosure record for new disclosures" do
      expect { importer.call }.to change(Disclosure, :count).by(1)
    end

    it "returns the count of imported disclosures" do
      expect(importer.call).to eq(1)
    end

    it "is idempotent (re-running skips existing source_ids)" do
      importer.call
      expect { importer.call }.not_to change(Disclosure, :count)
    end

    it "triggers attachment download for new disclosures" do
      importer.call
      expect(downloader).to have_received(:call).once
    end

    it "stores the source_id on the disclosure" do
      importer.call
      expect(Disclosure.last.source_id).to eq("99001")
    end
  end
end
