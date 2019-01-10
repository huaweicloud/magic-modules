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
end
