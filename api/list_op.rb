require 'api/object'

module Api
  # Represents a list operation definition
  class ListOp < Api::Object
    attr_reader :path
    attr_reader :query_params
    # an array with items that uniquely identify the resource.
    attr_reader :identity
    attr_reader :msg_prefix

    def validate
      super

      check_property :path, String
      check_property :identity, Array
      check_property_list :identity, String
      check_optional_property :query_params, Array
      check_optional_property_list :query_params, String
      check_optional_property :msg_prefix, String

    end

    def check_identity
      # Ensures we have all properties defined
      @identity.each do |i|
        raise "Missing property for identity(#{i}) in list operation of resource (#{@__resource.name})" \
          if @__resource.properties.index { |p| p.name == i }.nil?
      end
    end
  end
end
