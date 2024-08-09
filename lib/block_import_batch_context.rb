class BlockImportBatchContext
  class << self
    @imported_facet_transactions = Concurrent::Array.new
    @imported_facet_transaction_receipts = Concurrent::Array.new
  end
  
  def self.imported_facet_transactions
    @imported_facet_transactions
  end
  
  def self.imported_facet_transaction_receipts
    @imported_facet_transaction_receipts
  end
  
  def self.set(
    imported_facet_transactions:,
    imported_facet_transaction_receipts:
  )
    old_imported_facet_transactions = @imported_facet_transactions
    old_imported_facet_transaction_receipts = @imported_facet_transaction_receipts
    
    @imported_facet_transactions = imported_facet_transactions
    @imported_facet_transaction_receipts = imported_facet_transaction_receipts
    yield
  ensure
    @imported_facet_transactions = old_imported_facet_transactions
    @imported_facet_transaction_receipts = old_imported_facet_transaction_receipts
  end
end
