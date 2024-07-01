class FacetTransactionsController < ApplicationController
  def index
    @facet_transactions = FacetTransaction.order(block_number: :desc).limit(25)
    render json: @facet_transactions
  end
  
  def in_eth_tx
    eth_tx_hash = params[:id]
    eth_tx = EthTransaction.where(tx_hash: eth_tx_hash).includes(facet_transactions: :facet_transaction_receipt)
    
    res = {
      result: eth_tx.first.as_json(include: { 
        facet_transactions: { 
          include: :facet_transaction_receipt 
        } 
      })
    }
    
    render json: res
  end
  
  def rpc_proxy
    res = GethDriver.client.call(params[:method], params[:params])
    
    render json: { result: res }
  rescue GethClient::ClientError => e
    render json: { error: e.message }, status: :bad_request
  end
end
