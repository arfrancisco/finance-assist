# Automatically inject MCP_API_KEY header into GraphiQL IDE (development only)
if defined?(GraphiQL::Rails)
  GraphiQL::Rails.config.headers = lambda { |_context|
    { "Authorization" => "Bearer #{ENV['MCP_API_KEY']}" }
  }
end
