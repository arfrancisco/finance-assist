Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  resources :stocks,       only: [:index, :show]
  resources :daily_prices, only: [:index]
  resources :disclosures,  only: [:index, :show]
  resources :predictions,  only: [:index]
  resources :self_audits,  only: [:index]

  # Read-only GraphQL API (requires Authorization: Bearer <MCP_API_KEY>)
  post "/graphql", to: "graphql#execute"

  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end
end
