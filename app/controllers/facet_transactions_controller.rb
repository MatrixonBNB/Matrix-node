class FacetTransactionsController < ApplicationController
  def index
    @facet_transactions = FacetTransaction.order(block_number: :desc).limit(25)
    render json: @facet_transactions
  end
end
