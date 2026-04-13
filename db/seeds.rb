# Seed a placeholder model version so predictions can be created during smoke tests
# and Phase 1 development before real scoring weights are defined in Phase 2.
ModelVersion.find_or_create_by!(version_name: "v0-placeholder") do |mv|
  mv.description = "Placeholder model version for Phase 1 development and smoke testing. No real weights defined."
  mv.algorithm_type = "placeholder"
  mv.weights_json = {}
  mv.notes = "Replace with a real versioned model in Phase 2 when factor scoring is implemented."
end

puts "Seeded model_versions: #{ModelVersion.count} record(s)"
