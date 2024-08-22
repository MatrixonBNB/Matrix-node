Rails.application.routes.draw do
  post 'rpc', to: 'facet_transactions#rpc'
  
  get 'legacy_value_mappings/lookup', to: 'legacy_value_mappings#lookup'
  get 'legacy_value_mappings/contract_artifacts', to: 'legacy_value_mappings#contract_artifacts'
  
  resources :eth_transactions, only: [:show]
  resources :facet_blocks, only: [:index]
  resources :facet_transactions, only: [:index]
end
