class FacetBlocksController < ApplicationController
  def index
    @facet_blocks = FacetBlock.order(number: :desc).limit(25)
    render json: @facet_blocks
  end
end
