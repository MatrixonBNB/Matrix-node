class LegacyValueMappingsController < ApplicationController
  def lookup
    mapping_type = params[:mapping_type]
    legacy_value = params[:legacy_value]

    legacy_value_mapping = LegacyValueMapping.find_by(
      mapping_type: mapping_type,
      legacy_value: legacy_value
    )

    if legacy_value_mapping
      render json: { new_value: legacy_value_mapping.new_value }
    else
      render json: { error: 'Mapping not found' }, status: :not_found
    end
  end
end
