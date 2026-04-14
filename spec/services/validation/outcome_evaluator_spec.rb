require "rails_helper"

RSpec.describe Validation::OutcomeEvaluator do
  let(:evaluator) { described_class.new }
  let(:model_version) { create(:model_version) }
  let(:stock) { create(:stock, symbol: "ALI") }
  let(:as_of_date) { Date.new(2024, 1, 2) }

  # Seed prices for the stock over a window that covers short horizon (5 days)
  def seed_prices(stock, from:, to:, base_close: 10.0, trend: 0.005)
    (from..to).each_with_index do |date, i|
      next if date.saturday? || date.sunday?
      close = (base_close * (1 + i * trend)).round(4)
      create(:daily_price, stock: stock, trading_date: date, close: close, adjusted_close: close)
    end
  end

  before do
    seed_prices(stock, from: as_of_date, to: as_of_date + 10)
  end

  let(:prediction) do
    create(:prediction,
      stock: stock,
      model_version: model_version,
      as_of_date: as_of_date,
      horizon: "short",
      rank_position: 1,
      total_score: 0.5,
      confidence: 0.6
    )
  end

  describe "#call" do
    context "when horizon has elapsed" do
      before { prediction }  # force creation

      it "creates a PredictionOutcome" do
        expect { evaluator.call }.to change(PredictionOutcome, :count).by(1)
      end

      it "returns the count of evaluated predictions" do
        expect(evaluator.call).to eq(1)
      end

      it "sets entry_price from as_of_date" do
        evaluator.call
        outcome = PredictionOutcome.last
        expected = stock.daily_prices.find_by(trading_date: as_of_date).close.to_f
        expect(outcome.entry_price.to_f).to eq(expected)
      end

      it "sets raw_return" do
        evaluator.call
        expect(PredictionOutcome.last.raw_return).not_to be_nil
      end

      it "sets was_positive based on raw_return" do
        evaluator.call
        outcome = PredictionOutcome.last
        expect(outcome.was_positive).to eq(outcome.raw_return.to_f > 0)
      end

      it "sets outcome_label" do
        evaluator.call
        expect(%w[win loss neutral]).to include(PredictionOutcome.last.outcome_label)
      end

      it "is idempotent — re-running does not create duplicate outcomes" do
        evaluator.call
        expect { evaluator.call }.not_to change(PredictionOutcome, :count)
      end
    end

    context "when horizon has not yet elapsed" do
      let(:as_of_date) { Date.today }

      it "does not create an outcome" do
        expect { evaluator.call }.not_to change(PredictionOutcome, :count)
      end
    end

    context "when price data is missing for the exit date" do
      before do
        # Remove prices after as_of_date so no exit price can be found
        stock.daily_prices.where("trading_date > ?", as_of_date).delete_all
      end

      it "does not create an outcome and does not raise" do
        expect { evaluator.call }.not_to change(PredictionOutcome, :count)
      end
    end
  end
end
