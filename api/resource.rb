# 2018.05.31 - added properties of create_codes etc to resource
#
# Copyright 2017 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'api/object'
require 'google/string_utils'

module Api
  # An object available in the product
  # rubocop:disable Metrics/ClassLength
  class Resource < Api::Object::Named
    # The list of properties (attr_reader) that can be overridden in
    # <provider>.yaml.
    module Properties
      include Api::Object::Named::Properties

      attr_reader :description
      attr_reader :kind
      attr_reader :base_url
      attr_reader :self_link
      attr_reader :self_link_query
      # identity: an array with items that uniquely identify the resource.
      # default=name
      attr_reader :identity
      attr_reader :exclude
      attr_reader :virtual
      attr_reader :readonly
      attr_reader :exports
      attr_reader :label_override
      attr_reader :transport
      attr_reader :references
      attr_reader :input # If true, resource is not updatable as a whole unit
      attr_reader :create_codes # the successful codes of Create
      attr_reader :update_codes # the successful codes of Update
      attr_reader :get_codes    # the successful codes of Get
      attr_reader :delete_codes # the successful codes of Delete
      attr_reader :apis
      attr_reader :version
    end

    include Properties

    # Parameters can be overridden via Provider::PropertyOverride
    # A custom getter is used for :parameters instead of `attr_reader`

    # Properties can be overridden via Provider::PropertyOverride
    # A custom getter is used for :properties instead of `attr_reader`

    attr_reader :__product

    # Allows overriding snowflake transport requests
    class Transport < Api::Object
      attr_reader :encoder
      attr_reader :decoder

      def validate
        super
        check_optional_property :encoder, ::String
        check_optional_property :decoder, ::String
      end
    end

    # Allows mapping of requests to specific API layout quirks.
    class Wrappers < Api::Object
      attr_reader :create

      def validate
        super
        check_property :create, ::String
      end
    end

    # Represents a response from the API that returns a list of objects.
    class ResponseList < Api::Object
      attr_reader :kind
      attr_reader :items

      def validate
        super
        check_property :kind, String
        check_property :items, String
      end

      def kind?
        !@kind.nil?
      end
    end

    # Represents a list of documentation links.
    class ReferenceLinks < Api::Object
      attr_reader :guides
      attr_reader :api

      def validate
        super

        @guides ||= {}

        check_property :guides, Hash

        check_optional_property :api, String
      end
    end

    # Represents a hierarchy that has an object as its key. For example, when
    # creating test data, we'll do it per type, so it would look like this in
    # the provider.yaml file:
    #
    # test_data: !ruby/object:Api::Resource::HashArray
    #   Object1:
    #     - data1
    #     - data2
    #   Object2:
    #     - data3
    #     - data4
    class HashArray < Api::Object
      def consume_api(api)
        @__api = api
      end

      def validate
        return unless @__objects.nil? # allows idempotency of calling validate
        convert_findings_to_hash
        ensure_keys_are_objects unless @__api.nil?
        super
      end

      def [](index)
        @__objects[index]
      end

      def each
        return enum_for(:each) unless block_given?
        @__objects.each { |o| yield o }
        self
      end

      def select
        return enum_for(:select) unless block_given?
        @__objects.select { |k, v| yield k, v }
      end

      def fetch(key, *args)
        # *args only holds default value. Needs to mimic ::Hash
        if args.empty?
          # KeyErorr will be thrown if key not found
          @__objects&.fetch(key)
        else
          # args[0] will be returned if key not found
          @__objects&.fetch(key, args[0])
        end
      end

      def key?(key)
        @__objects&.key?(key)
      end

      def keys
        @__objects.keys
      end

      private

      # Converts every variable into @__objects
      def convert_findings_to_hash
        @__objects = {}
        instance_variables.each do |var|
          next if var.id2name.start_with?('@__')
          @__objects[var.id2name[1..-1]] = instance_variable_get(var)
          remove_instance_variable(var)
        end
      end

      def ensure_keys_are_objects
        @__objects.each_key do |type|
          next unless @__api.objects.select { |o| o.name == type }.empty?
          raise [
            "Object #{type} is not a valid type.",
            "Allowed types are: #{@__api.objects.map(&:name)}"
          ].join(' ')
        end
      end
    end

    def out_name
      [@__product.prefix, Google::StringUtils.underscore(@name)].join('_')
    end

    def identity
      props = all_user_properties
      if @identity.nil?
        props.select { |p| p.name == Api::Type::String::NAME.name }
      else
        props.select { |p| @identity.include?(p.name) }
      end
    end

    # 'identity' is already taken by Ruby.
    def __identity
      @identity
    end

    # Main data validation. As the validation code is simple, but long due to
    # the number of properties, it is okay to ignore Rubocop warnings about
    # method size and complexity.
    #
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def validate
      super
      check_optional_property :base_url, String
      check_property :description, String
      check_optional_property :exclude, :boolean
      check_optional_property :kind, String
      check_optional_property :parameters, Array
      check_optional_property :exports, Array
      check_optional_property :self_link, String
      check_optional_property :self_link_query, Api::Resource::ResponseList
      check_optional_property :virtual, :boolean
      check_optional_property :readonly, :boolean
      check_optional_property :label_override, String
      check_optional_property :transport, Transport
      check_optional_property :references, ReferenceLinks
      check_optional_property :create_codes, Array
      check_optional_property :update_codes, Array
      check_optional_property :delete_codes, Array
      check_optional_property :get_codes, Array
      check_optional_property_list :create_codes, Integer
      check_optional_property_list :update_codes, Integer
      check_optional_property_list :delete_codes, Integer
      check_optional_property_list :get_codes, Integer
      check_optional_property :version, String
      @version ||= ""
      @version = @version.strip
      unless @version.empty?
        raise "version(#{@version}) must be in format of 'v[0-9]+'" if /^v[0-9]+$/.match(@version).nil?
      end
      check_property :apis, Hash


      @apis.each do |k, v|
        check_property_value "apis::#{k}", v, Api::ApiBasic
        v.check_more(self)
      end
      if read_api.nil? and list_api.nil?
        raise "no read api and list api for resource(#{@name})"
      end

      check_property :properties, Array unless @exclude

      check_optional_property :input, :boolean

      check_optional_property :input, :boolean

      set_variables(@parameters, :__resource)
      set_variables(@properties, :__resource)

      check_property_list :parameters, Api::Type
      check_property_list :properties, Api::Type

      check_identity unless @identity.nil?

      if properties.select(&:is_id).length > 1
        raise "There are more than one properties as the resource identifier"
      end
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    def properties
      (@properties || []).reject(&:exclude)
    end

    def parameters
      (@parameters || []).reject(&:exclude)
    end

    def alone_parameters
      (@parameters || []).reject(&:exclude).select(&:alone_parameter)
    end

    # Returns all properties and parameters including the ones that are
    # excluded. This is used for PropertyOverride validation
    def all_properties
      ((@properties || []) + (@parameters || []))
    end

    def all_user_properties
      properties + parameters
    end

    def required_properties
      all_user_properties.select(&:required)
    end

    def not_output_properties
      all_user_properties.reject(&:output)
    end

    def ex_properties
      properties.select(&:update_url)
    end

    def ex_properties_of(t)
      if t == 'external'
        ex_properties.select{|p1| p1&.ex_property_opts&.get_url}

      elsif t == 'internal'
        ex_properties.reject{|p1| p1&.ex_property_opts&.get_url}
      end

      raise 'unknown type to select external properties'
    end

    def resource_editable_properties
      properties.reject(&:output).reject(&:update_url).select { |p| p.crud.include?('u') }
    end

    def update_opts
      [
        parameters.reject(&:alone_parameter)&.select { |p| p.crud.include?('u') },
        resource_editable_properties,
      ].flatten.compact
    end

    def update_alone_opts
      alone_parameters.select { |p| p.crud.include?('u') }
    end

    def create_opts
      [
        parameters.reject(&:alone_parameter)&.select { |p| p.input || p.crud.include?('c') },
        properties.reject(&:output).select { |p| p.crud.include?('c') },
      ].flatten.compact
    end

    def create_internal_opts
      ex_properties_of('internal').reject{|p1| p1.crud.include?('c')}
    end

    def create_alone_opts
      alone_parameters.select { |p| p.input || p.crud.include?('c') }
    end

    def resource_id
      ps = properties.select(&:is_id)
      ps.empty? ? 'id' : ps[0].field
    end

    def parameter(name)
      ps = all_user_properties.select { |p| p.name == name }
      ps.length == 1 ? ps[0] : nil
    end

    def exported_properties
      return [] if @exports.nil?
      from_api = @exports.select { |e| e.is_a?(Api::Type::FetchedExternal) }
                         .each { |e| e.resource = self }
      prop_names = @exports - from_api
      all_user_properties.select { |p| prop_names.include?(p.name) }
                         .concat(from_api)
                         .sort_by(&:name)
    end

    # TODO(alexstephen): Update test_constants to use this function.
    # Returns all of the properties that are a part of the self_link or
    # collection URLs
    def uri_properties
      [@base_url, @__product.default_version.base_url].map do |url|
        parts = url.scan(/\{\{(.*?)\}\}/).flatten
        parts << 'name'
        parts.delete('project')
        parts.map { |pt| all_user_properties.select { |p| p.name == pt }[0] }
      end.flatten
    end

    def check_identity
      check_property :identity, Array

      # Ensures we have all properties defined
      @identity.each do |i|
        raise "Missing property/parameter for identity #{i}" \
          if all_user_properties.select { |p| p.name == i }.empty?
      end
    end

    # Returns all resourcerefs at any depth
    def all_resourcerefs
      resourcerefs_for_properties(all_user_properties, self)
    end

    def kind?
      !@kind.nil?
    end

    def encoder?
      !@transport&.encoder.nil?
    end

    def decoder?
      !@transport&.decoder.nil?
    end

    # Returns true if this resource needs access to the saved API response
    # This response is stored in the @fetched variable
    # Requires:
    #   config: The config for an object
    #   object: An Api::Resource object
    def save_api_results?
      exported_properties.any? { |p| p.is_a? Api::Type::FetchedExternal } \
        || access_api_results
    end

    def find_property(path)
       return nil if (!path.is_a?(String) or path.empty?)
       v = path.split(".")

       o = @properties.find { |i| i.name.eql?(v[0]) }
       v.shift

       v.each do |name|
         return nil if o.nil?

         p = o.child_properties
         return nil if p.nil?

         o = p.find { |i| i.name.eql?(name) }
       end

       o
    end

    def create_api
      fetch_api("create")
    end

    def read_api
      fetch_api("read")
    end

    def update_api
      fetch_api("update")
    end

    def delete_api
      fetch_api("delete")
    end

    def list_api
      fetch_api("list")
    end

    def is_delete_api(api)
      api.name.eql? "delete"
    end

    def fetch_api(name)
      @apis.each do |_, v|
        return v if v.name.eql? name
      end

      return nil
    end

    private

    # Given an array of properties, return all ResourceRefs contained within
    # Requires:
    #   props- a list of props
    #   original_object - the original object containing props. This is to
    #                     avoid self-referencing objects.
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/PerceivedComplexity
    def resourcerefs_for_properties(props, original_obj)
      rrefs = []
      props.each do |p|
        # We need to recurse on ResourceRefs to get all levels
        # We do not want to recurse on resourcerefs of type self to avoid
        # infinite loop.
        if p.is_a? Api::Type::ResourceRef
          # We want to avoid a circular reference
          # This reference may be the next reference or have some number of refs
          # in between it.
          next if p.resource_ref == original_obj
          next if p.resource_ref == p.__resource
          rrefs << p
          rrefs.concat(resourcerefs_for_properties(p.resource_ref
                                                    .required_properties,
                                                   original_obj))
        elsif p.is_a? Api::Type::NestedObject
          rrefs.concat(resourcerefs_for_properties(p.properties, original_obj))
        elsif p.is_a? Api::Type::Array
          if p.item_type.is_a? Api::Type::NestedObject
            rrefs.concat(resourcerefs_for_properties(p.item_type.properties,
                                                     original_obj))
          elsif p.item_type.is_a? Api::Type::ResourceRef
            rrefs << p.item_type
            rrefs.concat(resourcerefs_for_properties(p.item_type.resource_ref
                                                      .required_properties,
                                                     original_obj))
          end
        end
      end
      rrefs.uniq
    end

    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/PerceivedComplexity
  end
  # rubocop:enable Metrics/ClassLength
end
