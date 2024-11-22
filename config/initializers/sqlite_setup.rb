Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.adapter_name.downcase.starts_with?('sqlite')
    ActiveRecord::Migration.verbose = false
    ActiveRecord::MigrationContext.new("db/migrate/").migrate
  end
end
