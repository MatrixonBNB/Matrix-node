class EthTransactionsController < ApplicationController
  def show
    eth_tx_hash = params[:id]
    eth_tx = EthTransaction.includes(facet_transactions: :facet_transaction_receipt).find_by(tx_hash: eth_tx_hash)
    
    unless eth_tx
      render json: { error: "Transaction not found" }, status: :not_found
      return
    end
    
    res = {
      result: eth_tx.as_json(include: { 
        facet_transactions: { 
          include: :facet_transaction_receipt 
        } 
      })
    }
    
    render json: res
  end
end
