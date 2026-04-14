require "rails_helper"

RSpec.describe Validation::SelfAudit do
  let(:audit) { described_class.new }
  let(:model_version) { create(:model_version) }

  def create_outcome(stock:, horizon:, beat_benchmark:, raw_return:, excess_return:, confidence:)
    prediction = create(:prediction,
      stock: stock,
      model_version: model_version,
      as_of_date: Date.today - 10,
      horizon: horizon,
      total_score: 0.5,
      confidence: confidence
    )
    create(:prediction_outcome,
      prediction: prediction,
      evaluation_date: Date.today - 5,
      entry_price: 10.0,
      exit_price: 10.0 * (1 + raw_return),
      raw_return: raw_return,
      benchmark_return: raw_return - excess_return,
      excess_return: excess_return,
      max_drawdown: -0.01,
      was_positive: raw_return > 0,
      beat_benchmark: beat_benchmark,
      outcome_label: beat_benchmark ? "win" : "loss"
    )
  end

  before do
    5.times do
      stock = create(:stock)
      create_outcome(stock: stock, horizon: "short", beat_benchmark: true,
                     raw_return: 0.05, excess_return: 0.03, confidence: 0.7)
    end
    3.times do
      stock = create(:stock)
      create_outcome(stock: stock, horizon: "short", beat_benchmark: false,
                     raw_return: -0.02, excess_return: -0.03, confidence: 0.4)
    end
  end

  describe "#call" do
    it "creates a SelfAuditRun for the short horizon" do
      expect { audit.call }.to change(SelfAuditRun, :count).by(1)
    end

    it "returns the number of runs created" do
      expect(audit.call).to eq(1)
    end

    it "computes hit_rate correctly (5 wins out of 8)" do
      audit.call
      run = SelfAuditRun.last
      expect(run.hit_rate.to_f.round(4)).to eq((5.0 / 8).round(4))
    end

    it "computes avg_return" do
      audit.call
      expect(SelfAuditRun.last.avg_return).not_to be_nil
    end

    it "computes avg_excess_return" do
      audit.call
      expect(SelfAuditRun.last.avg_excess_return).not_to be_nil
    end

    it "computes brier_score" do
      audit.call
      expect(SelfAuditRun.last.brier_score).not_to be_nil
    end

    it "sets summary_text" do
      audit.call
      expect(SelfAuditRun.last.summary_text).to include("Short-horizon audit")
    end

    it "sets calibration_notes" do
      audit.call
      expect(SelfAuditRun.last.calibration_notes).to be_present
    end

    context "with fewer than MIN_SAMPLE outcomes" do
      before { PredictionOutcome.delete_all; Prediction.delete_all }

      it "does not create a SelfAuditRun" do
        expect { audit.call }.not_to change(SelfAuditRun, :count)
      end

      it "returns 0" do
        expect(audit.call).to eq(0)
      end
    end
  end
end
