class RenameHorizonValues < ActiveRecord::Migration[7.1]
  RENAME = { "short" => "5d", "medium" => "20d", "long" => "60d" }.freeze

  def up
    %w[feature_snapshots predictions self_audit_runs].each do |table|
      RENAME.each do |old_val, new_val|
        execute "UPDATE #{table} SET horizon = '#{new_val}' WHERE horizon = '#{old_val}'"
      end
    end

    ModelVersion.find_each do |mv|
      next unless mv.weights_json.is_a?(Hash)
      new_weights = mv.weights_json.transform_keys { |k| RENAME[k] || k }
      mv.update_columns(weights_json: new_weights)
    end
  end

  def down
    reverse = RENAME.invert
    %w[feature_snapshots predictions self_audit_runs].each do |table|
      reverse.each do |old_val, new_val|
        execute "UPDATE #{table} SET horizon = '#{new_val}' WHERE horizon = '#{old_val}'"
      end
    end

    ModelVersion.find_each do |mv|
      next unless mv.weights_json.is_a?(Hash)
      new_weights = mv.weights_json.transform_keys { |k| reverse[k] || k }
      mv.update_columns(weights_json: new_weights)
    end
  end
end
