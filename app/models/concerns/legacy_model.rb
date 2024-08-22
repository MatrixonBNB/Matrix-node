module LegacyModel
  extend ActiveSupport::Concern

  included do
    if ENV['FACET_V1_VM_DATABASE_URL']
      establish_connection :secondary
    end
    
    before_save :raise_readonly_error
    before_destroy :raise_readonly_error
  end

  def readonly?
    true
  end

  private

  def raise_readonly_error
    raise ActiveRecord::ReadOnlyRecord
  end
end
