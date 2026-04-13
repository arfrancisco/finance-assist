require "rails_helper"

RSpec.describe Prediction, type: :model do
  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:prediction)).to be_valid
    end

    it "requires as_of_date" do
      expect(build(:prediction, as_of_date: nil)).not_to be_valid
    end

    it "requires horizon to be short/medium/long" do
      expect(build(:prediction, horizon: "invalid")).not_to be_valid
    end

    it "requires total_score" do
      expect(build(:prediction, total_score: nil)).not_to be_valid
    end
  end

  describe "immutability" do
    it "raises an error on update" do
      prediction = create(:prediction)
      expect { prediction.update!(rank_position: 99) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "associations" do
    it "belongs to a stock" do
      prediction = create(:prediction)
      expect(prediction.stock).to be_a(Stock)
    end

    it "belongs to a model_version" do
      prediction = create(:prediction)
      expect(prediction.model_version).to be_a(ModelVersion)
    end

    it "has one prediction_report" do
      expect(create(:prediction)).to respond_to(:prediction_report)
    end
  end
end
