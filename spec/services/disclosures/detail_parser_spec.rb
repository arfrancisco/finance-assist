require "rails_helper"

RSpec.describe Disclosures::PseEdge::DetailParser do
  let(:html) do
    <<~HTML
      <html><body>
      <div class="disclosure-content">
        <p>This is the annual report content for Ayala Land.</p>
        <a href="/downloads/ALI_2023.pdf">Download PDF</a>
        <a href="https://edge.pse.com.ph/attachment/file.pdf">Another PDF</a>
      </div>
      </body></html>
    HTML
  end

  subject(:parser) { described_class.new(html) }

  describe "#parse" do
    it "returns a hash with body_text and attachment_urls" do
      result = parser.parse
      expect(result).to have_key(:body_text)
      expect(result).to have_key(:attachment_urls)
    end

    it "extracts body text" do
      result = parser.parse
      expect(result[:body_text]).to include("annual report content")
    end

    it "extracts PDF attachment URLs" do
      result = parser.parse
      expect(result[:attachment_urls]).to include(
        a_string_matching(/\.pdf/)
      )
    end

    it "returns full URLs for relative links" do
      result = parser.parse
      expect(result[:attachment_urls]).to all(start_with("http"))
    end
  end
end
