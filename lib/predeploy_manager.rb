module PredeployManager
  extend self
  include Memery
  include SysConfig
  PREDEPLOY_INFO_PATH = Rails.root.join('config', 'predeploy_info.json')
  
  def predeploy_info
    parsed = JSON.parse(File.read(PREDEPLOY_INFO_PATH))
    
    result = {}
    parsed.each do |contract_name, info|
      contract = Eth::Contract.from_bin(
        name: info.fetch('name'),
        bin: info.fetch('bin'),
        abi: info.fetch('abi'),
      )
      
      addresses = Array.wrap(info['address'])
      addresses.each do |address|
        result[address] = contract.dup.tap { |c| c.address = address }.freeze
      end
      
      result[contract_name] = contract.freeze
    end
    
    result.freeze
  end
  memoize :predeploy_info
  
  def get_contract_from_predeploy_info(address: nil, name: nil)
    predeploy_info.fetch(address || name)
  end
  memoize :get_contract_from_predeploy_info
end
