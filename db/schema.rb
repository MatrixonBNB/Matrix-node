# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2024_06_28_125033) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "eth_blocks", force: :cascade do |t|
    t.bigint "number", null: false
    t.string "block_hash", null: false
    t.text "logs_bloom", null: false
    t.bigint "total_difficulty", null: false
    t.string "receipts_root", null: false
    t.string "extra_data", null: false
    t.string "withdrawals_root", null: false
    t.bigint "base_fee_per_gas", null: false
    t.string "nonce", null: false
    t.string "miner", null: false
    t.bigint "excess_blob_gas", null: false
    t.bigint "difficulty", null: false
    t.bigint "gas_limit", null: false
    t.bigint "gas_used", null: false
    t.string "parent_beacon_block_root", null: false
    t.integer "size", null: false
    t.string "transactions_root", null: false
    t.string "state_root", null: false
    t.string "mix_hash", null: false
    t.string "parent_hash", null: false
    t.bigint "blob_gas_used", null: false
    t.bigint "timestamp", null: false
    t.datetime "imported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_hash"], name: "index_eth_blocks_on_block_hash", unique: true
    t.index ["number"], name: "index_eth_blocks_on_number", unique: true
    t.check_constraint "block_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "parent_hash::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "eth_calls", force: :cascade do |t|
    t.integer "call_index", null: false
    t.integer "parent_call_index"
    t.bigint "block_number", null: false
    t.string "block_hash", null: false
    t.string "transaction_hash", null: false
    t.string "from_address", null: false
    t.string "to_address"
    t.bigint "gas"
    t.bigint "gas_used"
    t.text "input"
    t.text "output"
    t.decimal "value", precision: 78
    t.string "call_type"
    t.string "error"
    t.string "revert_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_hash", "call_index"], name: "index_eth_calls_on_block_hash_and_call_index", unique: true
    t.index ["block_hash", "parent_call_index"], name: "index_eth_calls_on_block_hash_and_parent_call_index"
    t.index ["block_hash"], name: "index_eth_calls_on_block_hash"
    t.index ["block_number"], name: "index_eth_calls_on_block_number"
    t.index ["transaction_hash"], name: "index_eth_calls_on_transaction_hash"
    t.check_constraint "block_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "from_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "to_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "transaction_hash::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "eth_transactions", force: :cascade do |t|
    t.string "block_hash", null: false
    t.bigint "block_number", null: false
    t.string "tx_hash", null: false
    t.integer "y_parity"
    t.jsonb "access_list"
    t.integer "transaction_index", null: false
    t.integer "tx_type", null: false
    t.integer "nonce", null: false
    t.text "input", null: false
    t.string "r", null: false
    t.string "s", null: false
    t.integer "chain_id"
    t.integer "v", null: false
    t.bigint "gas", null: false
    t.decimal "max_priority_fee_per_gas", precision: 78
    t.string "from_address", null: false
    t.string "to_address"
    t.decimal "max_fee_per_gas", precision: 78
    t.decimal "value", precision: 78, null: false
    t.decimal "gas_price", precision: 78
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_hash"], name: "index_eth_transactions_on_block_hash"
    t.index ["block_number"], name: "index_eth_transactions_on_block_number"
    t.index ["tx_hash"], name: "index_eth_transactions_on_tx_hash", unique: true
    t.check_constraint "block_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "from_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "to_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "tx_hash::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "facet_blocks", force: :cascade do |t|
    t.bigint "number", null: false
    t.string "block_hash", null: false
    t.string "eth_block_hash", null: false
    t.bigint "base_fee_per_gas", null: false
    t.string "extra_data", null: false
    t.bigint "gas_limit", null: false
    t.bigint "gas_used", null: false
    t.text "logs_bloom", null: false
    t.string "parent_beacon_block_root", null: false
    t.string "parent_hash", null: false
    t.string "receipts_root", null: false
    t.integer "size", null: false
    t.string "state_root", null: false
    t.integer "timestamp", null: false
    t.string "transactions_root", null: false
    t.string "prev_randao", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_hash"], name: "index_facet_blocks_on_block_hash", unique: true
    t.index ["eth_block_hash"], name: "index_facet_blocks_on_eth_block_hash", unique: true
    t.index ["number"], name: "index_facet_blocks_on_number", unique: true
    t.check_constraint "block_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "parent_hash::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "facet_transaction_receipts", force: :cascade do |t|
    t.string "transaction_hash", null: false
    t.string "block_hash", null: false
    t.integer "block_number", null: false
    t.string "contract_address"
    t.bigint "cumulative_gas_used", null: false
    t.string "deposit_nonce", null: false
    t.string "deposit_receipt_version", null: false
    t.bigint "effective_gas_price", null: false
    t.string "from_address", null: false
    t.bigint "gas_used", null: false
    t.jsonb "logs", default: [], null: false
    t.text "logs_bloom", null: false
    t.integer "status", null: false
    t.string "to_address"
    t.integer "transaction_index", null: false
    t.string "tx_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_hash"], name: "index_facet_transaction_receipts_on_block_hash"
    t.index ["block_number"], name: "index_facet_transaction_receipts_on_block_number"
    t.index ["transaction_hash"], name: "index_facet_transaction_receipts_on_transaction_hash", unique: true
    t.check_constraint "block_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "from_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "to_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "transaction_hash::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  create_table "facet_transactions", force: :cascade do |t|
    t.string "eth_transaction_hash", null: false
    t.integer "eth_call_index", null: false
    t.string "block_hash", null: false
    t.bigint "block_number", null: false
    t.string "deposit_receipt_version", null: false
    t.string "from_address", null: false
    t.bigint "gas", null: false
    t.bigint "gas_limit", null: false
    t.decimal "gas_price", precision: 78
    t.string "tx_hash", null: false
    t.text "input", null: false
    t.string "source_hash", null: false
    t.string "to_address"
    t.integer "transaction_index", null: false
    t.string "tx_type", null: false
    t.decimal "mint", precision: 78, null: false
    t.decimal "value", precision: 78, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["block_hash", "eth_call_index"], name: "index_facet_transactions_on_block_hash_and_eth_call_index", unique: true
    t.index ["block_hash"], name: "index_facet_transactions_on_block_hash"
    t.index ["block_number"], name: "index_facet_transactions_on_block_number"
    t.index ["eth_transaction_hash"], name: "index_facet_transactions_on_eth_transaction_hash"
    t.index ["tx_hash"], name: "index_facet_transactions_on_tx_hash", unique: true
    t.check_constraint "block_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "eth_transaction_hash::text ~ '^0x[a-f0-9]{64}$'::text"
    t.check_constraint "from_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "to_address::text ~ '^0x[a-f0-9]{40}$'::text"
    t.check_constraint "tx_hash::text ~ '^0x[a-f0-9]{64}$'::text"
  end

  add_foreign_key "eth_calls", "eth_blocks", column: "block_hash", primary_key: "block_hash", on_delete: :cascade
  add_foreign_key "eth_calls", "eth_transactions", column: "transaction_hash", primary_key: "tx_hash", on_delete: :cascade
  add_foreign_key "eth_transactions", "eth_blocks", column: "block_hash", primary_key: "block_hash", on_delete: :cascade
  add_foreign_key "facet_blocks", "eth_blocks", column: "eth_block_hash", primary_key: "block_hash", on_delete: :cascade
  add_foreign_key "facet_transaction_receipts", "facet_blocks", column: "block_hash", primary_key: "block_hash", on_delete: :cascade
  add_foreign_key "facet_transaction_receipts", "facet_transactions", column: "transaction_hash", primary_key: "tx_hash", on_delete: :cascade
  add_foreign_key "facet_transactions", "eth_transactions", column: "eth_transaction_hash", primary_key: "tx_hash", on_delete: :cascade
  add_foreign_key "facet_transactions", "facet_blocks", column: "block_hash", primary_key: "block_hash", on_delete: :cascade
end
