require 'api/object'

module Api
  # Represents a list operation definition
  class ApiObject < Api::Object
    attr_reader :path
    attr_reader :verb
    attr_reader :parameters

    def validate
      super
      check_property :path, String
      check_optional_property :verb, Symbol

      check_optional_property :parameters, Array
      unless @parameters.nil?
        check_property_list :parameters, Api::Type
      end

    end
  end

  class ListOp < Api::ApiObject
    attr_reader :query_params
    # an array with items that uniquely identify the resource.
    attr_reader :identity

    def validate
      super

      check_property :identity, Array
      check_property_list :identity, String
      check_optional_property :query_params, Array
      check_optional_property_list :query_params, String

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
