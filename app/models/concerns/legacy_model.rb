module LegacyModel
  extend ActiveSupport::Concern

  included do
    establish_connection :secondary
    
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
