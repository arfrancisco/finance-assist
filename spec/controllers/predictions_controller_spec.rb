require "rails_helper"

RSpec.describe PredictionsController, type: :request do
  let(:date) { Date.new(2026, 4, 15) }

  # Create 15 predictions for 20d horizon so we can verify the top-10 limit
  # and show-all behaviour. Each gets a unique rank and symbol via the factory.
  let!(:predictions_20d) do
    (1..15).map do |i|
      stock = create(:stock, symbol: "T#{i.to_s.rjust(2, '0')}")
      create(:prediction, stock: stock, horizon: "20d", as_of_date: date, rank_position: i)
    end
  end

  # A separate set for 5d horizon to verify horizon filtering
  let!(:predictions_5d) do
    stock = create(:stock, symbol: "FIVE")
    [create(:prediction, stock: stock, horizon: "5d", as_of_date: date, rank_position: 1)]
  end

  describe "GET /predictions" do
    it "returns 200" do
      get predictions_path
      expect(response).to have_http_status(:ok)
    end

    it "renders top 10 rows by default (20d horizon)" do
      get predictions_path(horizon: "20d", date: date.iso8601)
      # 15 predictions exist; only top 10 symbols should appear
      expect(response.body).to include("T01")
      expect(response.body).to include("T10")
      expect(response.body).not_to include("T11")
    end

    it "shows the View all link when in top-10 mode" do
      get predictions_path(horizon: "20d", date: date.iso8601)
      expect(response.body).to include("View all")
    end
  end

  describe "GET /predictions?show=all" do
    it "returns 200" do
      get predictions_path(show: "all", horizon: "20d", date: date.iso8601)
      expect(response).to have_http_status(:ok)
    end

    it "renders all 15 predictions" do
      get predictions_path(show: "all", horizon: "20d", date: date.iso8601)
      # All symbols T01–T15 should appear in the response
      (1..15).each do |i|
        expect(response.body).to include("T#{i.to_s.rjust(2, '0')}")
      end
    end

    it "shows the Back to top 10 link" do
      get predictions_path(show: "all", horizon: "20d", date: date.iso8601)
      expect(response.body).to include("Back to top 10")
    end
  end

  describe "GET /predictions?horizon=5d" do
    it "returns 200" do
      get predictions_path(horizon: "5d", date: date.iso8601)
      expect(response).to have_http_status(:ok)
    end

    it "shows the 5d stock and not 20d-only stocks" do
      get predictions_path(horizon: "5d", date: date.iso8601)
      expect(response.body).to include("FIVE")
      expect(response.body).not_to include("T01")
    end

    it "falls back to 20d for an unknown horizon" do
      get predictions_path(horizon: "invalid", date: date.iso8601)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("T01")
    end
  end

  describe "GET /predictions?symbol=" do
    it "filters to matching symbols only" do
      get predictions_path(show: "all", symbol: "T01", horizon: "20d", date: date.iso8601)
      expect(response.body).to include("T01")
      # T02–T15 should not appear (exact symbol match via ILIKE)
      expect(response.body).not_to include(">T02<")
    end

    it "returns an empty state for a symbol with no predictions" do
      get predictions_path(show: "all", symbol: "NOMATCH", date: date.iso8601)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No predictions found")
    end
  end

  describe "GET /predictions?date=" do
    it "returns 200 for a date with no predictions (renders empty state)" do
      get predictions_path(date: "2020-01-01")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No predictions found")
    end

    it "returns predictions for a known date" do
      get predictions_path(date: date.iso8601, horizon: "20d")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("T01")
    end
  end
end
