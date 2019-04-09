require 'api/object'

module Api
  # Represents a list operation definition
  class ApiBasic < Api::Object
    attr_reader :name
    attr_reader :path
    attr_reader :verb
    attr_reader :parameters
    attr_reader :async
    attr_reader :service_level
    attr_reader :service_type
    attr_reader :msg_prefix
    attr_reader :msg_prefix_array_items
    attr_reader :has_response

    def validate
      super

      check_property :name, String
      check_property :path, String
      check_property :service_type, String
      check_property :has_response, :boolean
      check_property_oneof :service_level, ["project", "domain"], String
      check_optional_property :verb, String

      check_optional_property :parameters, Array
      unless @parameters.nil?
        check_property_list :parameters, Api::Type
      end

      check_optional_property :async, Api::Async
      check_optional_property :msg_prefix, String
      check_optional_property :msg_prefix_array_items, Array
      unless @msg_prefix_array_items.nil?
        check_property_list :msg_prefix_array_items, String
      end
    end
  end

  class ApiCreate < Api::ApiBasic
    attr_reader :resource_id_path

    def validate
      super

      check_optional_property :resource_id_path, String
    end
  end

  class ApiList < Api::ApiBasic
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

  class ApiAction < Api::ApiBasic
    AFTER_SEND_CREATE_REQUEST = "after_send_create_request"

    attr_reader :when
    attr_reader :path_parameter

    def validate
      super

      check_property_oneof :when, [AFTER_SEND_CREATE_REQUEST], String

      check_optional_property :path_parameter, Hash
      if @path_parameter
        @path_parameter.each {|k, v| check_property_value("apiaction.path_parameter:#{k}", v, String)}
      end
    end
  end

  class ApiOther < Api::ApiBasic
    attr_reader :crud

    def validate
      super

      check_property :crud, String
    end
  end
end
