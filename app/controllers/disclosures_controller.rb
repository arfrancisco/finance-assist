class DisclosuresController < ApplicationController
  def index
    @disclosures = Disclosure.includes(:stock).order(disclosure_date: :desc, fetched_at: :desc).joins(:stock)

    @disclosures = @disclosures.where("stocks.symbol ILIKE ?", "%#{params[:symbol]}%") if params[:symbol].present?

    @disclosures = @disclosures.limit(200)
  end

  def show
    @disclosure = Disclosure.includes(:stock).find(params[:id])
  end
end
