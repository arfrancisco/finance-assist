class AddGuidanceAndEducationToPredictionReports < ActiveRecord::Migration[7.1]
  def change
    add_column :prediction_reports, :guidance_text, :text
    add_column :prediction_reports, :education_text, :text
  end
end
