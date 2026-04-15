class GraphqlController < ApplicationController
  # JSON API — no CSRF token from clients
  skip_before_action :verify_authenticity_token

  before_action :authenticate_api_key!

  def execute
    variables  = prepare_variables(params[:variables])
    query      = params[:query]
    op_name    = params[:operationName]
    context    = { current_request: request }

    result = FinanceAssistSchema.execute(
      query,
      variables:      variables,
      context:        context,
      operation_name: op_name
    )
    render json: result
  rescue StandardError => e
    raise e unless Rails.env.development?
    render json: { errors: [{ message: e.message, backtrace: e.backtrace.first(5) }] },
           status: :internal_server_error
  end

  private

  def authenticate_api_key!
    expected = ENV["MCP_API_KEY"]

    unless expected.present?
      render json: { errors: [{ message: "Server misconfiguration: MCP_API_KEY not set" }] },
             status: :internal_server_error
      return
    end

    token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip

    unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      render json: { errors: [{ message: "Unauthorized" }] }, status: :unauthorized
    end
  end

  def prepare_variables(variables_param)
    case variables_param
    when String
      variables_param.present? ? JSON.parse(variables_param) : {}
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash
    when nil
      {}
    end
  end
end
