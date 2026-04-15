require "rails_helper"

RSpec.describe Disclosures::PseEdge::Importer do
  let(:fetcher) { instance_double(Disclosures::PseEdge::Fetcher) }
  let(:downloader) { instance_double(Disclosures::PseEdge::AttachmentDownloader) }
  let(:importer) { described_class.new(fetcher: fetcher, downloader: downloader, pages: 1) }

  let(:listing_html) do
    <<~HTML
      <html><body>
      <table class="list">
        <tbody>
          <tr>
            <td><a onclick="openPopup('99001abcdef12')" href="#">Ayala Land Inc: 2023 Annual Report</a></td>
            <td>Jan 15, 2024 09:00 AM</td>
            <td>Annual Report</td>
            <td>PSE Form 17-A</td>
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

    it "does not trigger attachment downloads (skipped to conserve request budget)" do
      importer.call
      expect(downloader).not_to have_received(:call)
    end

    it "stores the source_id on the disclosure" do
      importer.call
      expect(Disclosure.last.source_id).to eq("99001abcdef12")
    end
  end
end
