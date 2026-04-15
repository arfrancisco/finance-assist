class AddPseEdgeNamesToStocks < ActiveRecord::Migration[7.1]
  def up
    add_column :stocks, :pse_edge_names, :string, array: true, default: []
    add_index :stocks, :pse_edge_names, using: :gin

    # Seed known aliases where PSE EDGE uses a name that can't be matched
    # by normalization alone (rebrands, abbreviations, word-order differences).
    {
      "PSE"   => ["PSE"],
      "ACEN"  => ["ACEN CORPORATION"],
      "SHLPH" => ["Shell Pilipinas Corporation"],
      "SUN"   => ["Suntrust Resort Holdings, Inc."],
    }.each do |symbol, aliases|
      Stock.find_by(symbol: symbol)&.update_columns(pse_edge_names: aliases)
    end
  end

  def down
    remove_index :stocks, :pse_edge_names
    remove_column :stocks, :pse_edge_names
  end
end
