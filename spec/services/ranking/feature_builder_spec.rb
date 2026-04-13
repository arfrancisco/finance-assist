require "rails_helper"

RSpec.describe Ranking::FeatureBuilder do
  let(:stock) { create(:stock, symbol: "ALI") }
  let(:as_of_date) { Date.new(2024, 12, 31) }
  let(:horizon) { "short" }
  let(:builder) { described_class.new(stock: stock, as_of_date: as_of_date, horizon: horizon) }

  # Create 65 daily prices ending on as_of_date with a gentle uptrend
  before do
    base_close = 10.0
    65.times do |i|
      date = as_of_date - (64 - i)
      close = (base_close * (1 + i * 0.001)).round(4)
      create(:daily_price,
        stock: stock,
        trading_date: date,
        open: close - 0.05,
        high: close + 0.10,
        low: close - 0.10,
        close: close,
        adjusted_close: close,
        volume: 1_000_000 + (i * 10_000)
      )
    end
  end

  describe "#call" do
    it "returns a FeatureSnapshot" do
      result = builder.call
      expect(result).to be_a(FeatureSnapshot)
    end

    it "creates exactly one FeatureSnapshot row" do
      expect { builder.call }.to change(FeatureSnapshot, :count).by(1)
    end

    it "sets feature_version to v1" do
      expect(builder.call.feature_version).to eq("v1")
    end

    it "computes positive momentum for an uptrending stock" do
      snapshot = builder.call
      expect(snapshot.momentum_5d).to be > 0
      expect(snapshot.momentum_20d).to be > 0
      expect(snapshot.momentum_60d).to be > 0
    end

    it "computes positive volatility_20d" do
      expect(builder.call.volatility_20d).to be > 0
    end

    it "computes positive avg_volume_20d" do
      expect(builder.call.avg_volume_20d).to be > 0
    end

    it "sets catalyst_score between 0 and 1" do
      score = builder.call.catalyst_score
      expect(score).to be >= 0
      expect(score).to be <= 1
    end

    it "leaves total_score nil (Scorer fills it in)" do
      expect(builder.call.total_score).to be_nil
    end

    it "is idempotent — re-running does not create duplicate rows" do
      builder.call
      expect { builder.call }.not_to change(FeatureSnapshot, :count)
    end

    it "updates feature values on re-run" do
      first = builder.call
      # Re-run should update, not error
      second = builder.call
      expect(second.id).to eq(first.id)
    end

    context "with insufficient price data" do
      before { stock.daily_prices.delete_all }

      it "returns nil and does not raise" do
        expect(builder.call).to be_nil
      end

      it "does not create a FeatureSnapshot" do
        expect { builder.call }.not_to change(FeatureSnapshot, :count)
      end
    end

    context "with fundamentals" do
      before do
        create(:fundamental, stock: stock, period_type: "annual",
               period_end_date: as_of_date - 30, pe: 10.0, roe: 15.0)
      end

      it "computes valuation_score" do
        expect(builder.call.valuation_score).to be > 0
      end

      it "computes quality_score" do
        expect(builder.call.quality_score).to be > 0
      end
    end
  end
end
