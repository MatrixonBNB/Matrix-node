class EthBlock < ApplicationRecord
  has_many :eth_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_many :eth_calls, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_many :facet_blocks, primary_key: :block_hash, foreign_key: :eth_block_hash, dependent: :destroy
end
