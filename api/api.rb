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
    attr_reader :header_params

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

      check_optional_property :header_params, Hash
    end

    def find_parameter(path)
       return nil if @parameters.nil?

       return nil if (!path.is_a?(String) or path.empty?)
       v = path.split(".")

       o = @parameters.find { |i| i.name.eql?(v[0]) }
       v.shift

       v.each do |name|
         return nil if o.nil?

         p = o.child_properties
         return nil if p.nil?

         o = p.find { |i| i.name.eql?(name) }
       end

       o
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
    attr_reader :resource_id_path

    def validate
      super

      check_optional_property :identity, Hash # only terraform needs it
      check_property :resource_id_path, String
      check_optional_property :query_params, Hash
    end

    def check_identity
      return if @identity.nil?

      # Ensures we have all properties defined
      @identity.each do |k, v|
        next if k.eql?("id")

        p = @__resource.find_property(v)
        if p.nil?
          raise "Missing property(#{v}) for identity(#{k}) in list operation of resource (#{@__resource.name})"
        end

        unless p.required
          raise "property(#{v}) referenced by list identity(#{k}) must be a required option"
        end
      end

      check_query_params
    end

    def known_query_params
      ["marker", "offset", "start", "limit"]
    end

    def pagination_param
      r = Hash.new
      @query_params.each do |k, v|
        if ["marker", "offset", "start"].include?(v)
          r[k] = v
        end
      end

      if r.length > 1
        raise "there should be only one pagination parameter"
      end

      r.each do |k, v|
        return k, v
      end

      return "", ""
    end

    private

    def check_query_params
      return if @query_params.nil?

      qp = known_query_params

      # Ensures we have all properties defined
      @query_params.each do |k, v|
        next if qp.include?(k)

        p = @__resource.find_property(v)

        if p.nil?
          raise "Missing property(#{v}) for query_params(#{k}) in list operation of resource (#{@__resource.name})"
        end

        unless p.crud.include?("c") || p.crud.include?("u")
          raise "property(#{v}) referenced by list query_params(#{k}) must be an input option"
        end
      end

      pagination_param
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
