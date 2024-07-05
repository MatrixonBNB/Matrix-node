class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  connects_to database: { writing: :primary, reading: :secondary }
  
  def self.connected_to_primary?
    connection.current_database == ActiveRecord::Base.configurations[Rails.env]['primary']['database']
  end

  def self.connected_to_secondary?
    connection.current_database == ActiveRecord::Base.configurations[Rails.env]['secondary']['database']
  end
  
  def self.reading
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end
end
