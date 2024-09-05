namespace :geth do
  desc "Print the Geth init command"
  task :init_command => :environment do
    puts GethDriver.init_command
  end
end
