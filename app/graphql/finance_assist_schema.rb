class FinanceAssistSchema < GraphQL::Schema
  query Types::QueryType

  # No mutations — read-only API
  mutation nil

  # Prevent runaway nested queries
  max_depth 10
  max_complexity 300
end
