require_relative '../extensions/eth_rb_extensions'

namespace :geth do
  desc "Print the Geth init command"
  task :init_command => :environment do
    if ENV["G"].present?
      PredeployManager.write_genesis_json
    end
    
    puts GethDriver.init_command
  end
  
  desc "Generate genesis files"
  task :generate_genesis => :environment do
    PredeployManager.write_genesis_json
  end
end
