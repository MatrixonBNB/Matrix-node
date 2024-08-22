class LegacyValueMappingsController < ApplicationController
  def lookup
    legacy_value = params[:legacy_value]

    legacy_value_mapping = LegacyValueMapping.find_by(
      legacy_value: legacy_value
    )

    if legacy_value_mapping
      render json: { new_value: legacy_value_mapping.new_value }
    else
      render json: { error: 'Mapping not found' }, status: :not_found
    end
  end
end
