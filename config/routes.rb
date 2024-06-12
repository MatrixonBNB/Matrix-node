Rails.application.routes.draw do
  resources :facet_blocks, only: [:index]
  resources :facet_transactions, only: [:index]
  # ... other routes ...
end
