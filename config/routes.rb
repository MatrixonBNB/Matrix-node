Rails.application.routes.draw do
  resources :facet_blocks, only: [:index]
  resources :facet_transactions, only: [:index] do
    collection do
      get 'in_eth_tx/:id', to: 'facet_transactions#in_eth_tx', as: :in_eth_tx
    end
  end
  
end
