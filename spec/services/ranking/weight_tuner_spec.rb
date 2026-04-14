require "rails_helper"

RSpec.describe Ranking::WeightTuner do
  let(:base_weights) do
    {
      "short"  => { "momentum_5d" => 0.4, "momentum_20d" => 0.2, "volatility_20d" => -0.2,
                    "relative_strength" => 0.1, "quality_score" => 0.1 },
      "medium" => { "momentum_20d" => 0.3, "momentum_60d" => 0.2, "relative_strength" => 0.2,
                    "valuation_score" => 0.15, "quality_score" => 0.15 },
      "long"   => { "momentum_60d" => 0.2, "valuation_score" => 0.25, "quality_score" => 0.25,
                    "relative_strength" => 0.2, "catalyst_score" => 0.1 }
    }
  end

  let(:base_model) { create(:model_version, version_name: "v1", weights_json: base_weights) }
  let(:tuner) { described_class.new(base_model_version: base_model) }

  def seed_outcome_with_snapshot(horizon:, excess_return:, momentum_5d:, momentum_20d: 0.0,
                                  momentum_60d: 0.0, volatility_20d: 0.01,
                                  relative_strength: 0.0, valuation_score: 0.5,
                                  quality_score: 0.5, catalyst_score: 0.2)
    stock      = create(:stock)
    model_ver  = create(:model_version)
    as_of_date = Date.today - 30

    create(:feature_snapshot,
      stock: stock, as_of_date: as_of_date, horizon: horizon, feature_version: "v1",
      momentum_5d: momentum_5d, momentum_20d: momentum_20d, momentum_60d: momentum_60d,
      volatility_20d: volatility_20d, relative_strength: relative_strength,
      valuation_score: valuation_score, quality_score: quality_score,
      catalyst_score: catalyst_score, avg_volume_20d: 1_000_000,
      risk_score: volatility_20d, liquidity_score: nil, total_score: nil
    )

    prediction = create(:prediction,
      stock: stock, model_version: model_ver,
      as_of_date: as_of_date, horizon: horizon,
      total_score: 0.5, confidence: 0.6
    )

    create(:prediction_outcome,
      prediction: prediction,
      evaluation_date: Date.today - 25,
      excess_return: excess_return,
      raw_return: excess_return + 0.01,
      was_positive: excess_return > 0,
      beat_benchmark: excess_return > 0,
      outcome_label: excess_return > 0 ? "win" : "loss"
    )
  end

  describe "#call" do
    context "with sufficient outcomes" do
      before do
        # 30 short-horizon outcomes where high momentum_5d correlates with positive excess return
        15.times { seed_outcome_with_snapshot(horizon: "short", excess_return: 0.05, momentum_5d: 0.08) }
        15.times { seed_outcome_with_snapshot(horizon: "short", excess_return: -0.03, momentum_5d: -0.02) }
      end

      it "creates a new ModelVersion" do
        result = tuner.call
        expect(result).to be_a(ModelVersion)
      end

      it "assigns a version name with a higher number than v1" do
        result = tuner.call
        num = result.version_name.match(/\Av(\d+)\z/)&.[](1)&.to_i
        expect(num).to be > 1
      end

      it "stores weights_json with horizon keys" do
        result = tuner.call
        expect(result.weights_json.keys).to include("short")
      end
    end

    context "with insufficient outcomes" do
      before do
        5.times { seed_outcome_with_snapshot(horizon: "short", excess_return: 0.02, momentum_5d: 0.05) }
      end

      it "returns nil" do
        expect(tuner.call).to be_nil
      end

      it "does not create a new ModelVersion" do
        tuner.call
        expect(ModelVersion.where(algorithm_type: "correlation_tuned").count).to eq(0)
      end
    end
  end
end
