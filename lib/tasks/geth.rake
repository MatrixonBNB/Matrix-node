namespace :geth do
  desc "Print the Geth init command"
  task :init_command do
    require_relative '../geth_driver'
    puts GethDriver.init_command
  end
end
