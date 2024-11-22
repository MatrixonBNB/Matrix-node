module MigrationExtensions
  def sqlite_adapter?
    ActiveRecord::Base.connection.adapter_name.downcase.starts_with?('sqlite')
  end

  def pg_adapter?
    ActiveRecord::Base.connection.adapter_name.downcase.starts_with?('postgresql')
  end
end

ActiveRecord::Migration.prepend(MigrationExtensions)
