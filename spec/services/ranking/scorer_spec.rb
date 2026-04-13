require "rails_helper"

RSpec.describe Ranking::Scorer do
  let(:weights_json) do
    {
      "short" => {
        "momentum_5d"       => 0.40,
        "momentum_20d"      => 0.20,
        "volatility_20d"    => -0.20,
        "relative_strength" => 0.10,
        "liquidity_score"   => 0.10
      },
      "medium" => {
        "momentum_20d"      => 0.30,
        "momentum_60d"      => 0.20,
        "relative_strength" => 0.20,
        "valuation_score"   => 0.15,
        "quality_score"     => 0.15
      },
      "long" => {
        "momentum_60d"      => 0.20,
        "valuation_score"   => 0.25,
        "quality_score"     => 0.25,
        "relative_strength" => 0.20,
        "catalyst_score"    => 0.10
      }
    }
  end

  let(:model_version) { create(:model_version, weights_json: weights_json) }
  let(:scorer) { described_class.new(model_version: model_version) }

  def build_snapshot(stock:, **overrides)
    create(:feature_snapshot,
      stock: stock,
      as_of_date: Date.new(2024, 12, 31),
      horizon: "short",
      feature_version: "v1",
      momentum_5d: 0.02,
      momentum_20d: 0.05,
      momentum_60d: 0.10,
      volatility_20d: 0.015,
      avg_volume_20d: 1_000_000,
      relative_strength: 0.01,
      valuation_score: 0.5,
      quality_score: 0.6,
      liquidity_score: nil,
      catalyst_score: 0.4,
      risk_score: 0.015,
      total_score: nil,
      **overrides
    )
  end

  describe "#call" do
    let(:stock) { create(:stock) }
    let(:snapshot) { build_snapshot(stock: stock) }

    it "returns a Prediction" do
      expect(scorer.call(feature_snapshot: snapshot)).to be_a(Prediction)
    end

    it "sets total_score" do
      prediction = scorer.call(feature_snapshot: snapshot)
      expect(prediction.total_score).not_to be_nil
    end

    it "sets predicted_direction" do
      prediction = scorer.call(feature_snapshot: snapshot)
      expect(%w[up down]).to include(prediction.predicted_direction)
    end

    it "sets recommendation_type" do
      prediction = scorer.call(feature_snapshot: snapshot)
      expect(%w[buy hold]).to include(prediction.recommendation_type)
    end

    it "sets benchmark_symbol to PSEI" do
      expect(scorer.call(feature_snapshot: snapshot).benchmark_symbol).to eq("PSEI")
    end

    it "copies feature_version from the snapshot" do
      expect(scorer.call(feature_snapshot: snapshot).feature_version).to eq("v1")
    end
  end

  describe "#call_batch" do
    let(:stocks) { create_list(:stock, 3) }
    let(:snapshots) do
      stocks.map { |s| build_snapshot(stock: s) }
    end

    it "creates one Prediction per snapshot" do
      expect { scorer.call_batch(feature_snapshots: snapshots) }
        .to change(Prediction, :count).by(3)
    end

    it "assigns rank_position to all predictions" do
      preds = scorer.call_batch(feature_snapshots: snapshots)
      expect(preds.map(&:rank_position)).to all(be_present)
    end

    it "assigns unique rank positions" do
      preds = scorer.call_batch(feature_snapshots: snapshots)
      ranks = preds.map(&:rank_position)
      expect(ranks.uniq.size).to eq(ranks.size)
    end

    it "is idempotent — re-running does not create duplicate Predictions" do
      scorer.call_batch(feature_snapshots: snapshots)
      expect { scorer.call_batch(feature_snapshots: snapshots) }
        .not_to change(Prediction, :count)
    end

    it "returns empty array for empty input" do
      expect(scorer.call_batch(feature_snapshots: [])).to eq([])
    end

    context "with mixed horizons" do
      let(:medium_snapshots) do
        stocks.map { |s| build_snapshot(stock: s, horizon: "medium") }
      end

      it "assigns ranks independently per horizon" do
        all = snapshots + medium_snapshots
        preds = scorer.call_batch(feature_snapshots: all)

        short_ranks  = preds.select { |p| p.horizon == "short"  }.map(&:rank_position).sort
        medium_ranks = preds.select { |p| p.horizon == "medium" }.map(&:rank_position).sort

        expect(short_ranks).to eq([1, 2, 3])
        expect(medium_ranks).to eq([1, 2, 3])
      end
    end
  end
end
