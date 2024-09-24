class Ethscription < T::Struct
  include EthscriptionEVMConverter
  include Memery
  
  REQUIRED_INITIAL_OWNER = "0x00000000000000000000000000000000000face7".freeze
  TRANSACTION_MIMETYPE = "application/vnd.facet.tx+json".freeze
  
  const :transaction_hash, String
  const :block_number, Integer
  const :block_blockhash, String
  const :transaction_index, Integer
  const :creator, String
  const :l1_tx_origin, String
  const :initial_owner, String
  const :content_uri, String
  
  def contract_initiated?
    l1_tx_origin != creator
  end
  
  def valid_data_uri?
    DataUri.valid?(content_uri)
  end
  
  def parsed_data_uri
    return unless valid_data_uri?
    DataUri.new(content_uri)
  end
  memoize :parsed_data_uri
  
  def content
    parsed_data_uri&.decoded_data
  end
    
  def block_hash
    block_blockhash
  end
  
  def parsed_content
    return unless content
    JSON.parse(content)
  end
  memoize :parsed_content
  
  def mimetype
    parsed_data_uri&.mimetype
  end
  
  def payload
    OpenStruct.new(JSON.parse(content))
  rescue JSON::ParserError, NoMethodError => e
  end
  memoize :payload
  
  def valid_to?
    initial_owner == REQUIRED_INITIAL_OWNER
  end
  
  def valid_mimetype?
    mimetype == TRANSACTION_MIMETYPE
  end
  
  def valid?
    v = valid_data_uri? &&
    valid_to? &&
    valid_mimetype? &&
    (payload.present? && payload.data&.is_a?(Hash))
    
    return false unless v
    
    op = payload.op&.to_sym
    data_keys = payload.data.keys.map(&:to_sym).to_set
    
    if op == :create
      unless [
        [:init_code_hash].to_set,
        [:init_code_hash, :args].to_set,
        
        [:init_code_hash, :source_code].to_set,
        [:init_code_hash, :source_code, :args].to_set
      ].include?(data_keys)
        return false
      end
    end
    
    if [:call, :static_call].include?(op)
      unless [
        [:to, :function].to_set,
        [:to, :function, :args].to_set
      ].include?(data_keys)
        return false
      end
      
      unless payload.data['to'].to_s.match(/\A0x[a-f0-9]{40}\z/i)
        return false
      end
    end
    
    unless DataUri.esip6?(content_uri)
      binding.irb
      raise
    end
    
    true
  end
end
