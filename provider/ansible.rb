# 2018.05.31 - changed method of 'module_name'
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

require 'provider/config'
require 'provider/core'
require 'provider/ansible/manifest'
require 'provider/ansible/example'
require 'provider/ansible/documentation'
require 'provider/ansible/module'
require 'provider/ansible/request'
require 'provider/ansible/resourceref'
require 'provider/ansible/resource_override'
require 'provider/ansible/property_override'
require 'provider/ansible/selflink'
require 'provider/ansible/sub_template'

module Provider
  module Ansible
    # Settings for the Ansible provider
    class Config < Provider::Config
      attr_reader :manifest

      def provider
        Provider::Ansible::Core
      end

      def resource_override
        Provider::Ansible::ResourceOverride
      end

      def property_override
        Provider::Ansible::PropertyOverride
      end

      def validate
        super
        check_optional_property :manifest, Provider::Ansible::Manifest
      end
    end

    # Code generator for Ansible Cookbooks that manage Google Cloud Platform
    # resources.
    # TODO(alexstephen): Split up class into multiple modules.
    # rubocop:disable Metrics/ClassLength
    class Core < Provider::Core
      PYTHON_TYPE_FROM_MM_TYPE = {
        'Api::Type::NestedObject' => 'dict',
        'Api::Type::Array' => 'list',
        'Api::Type::Boolean' => 'bool',
        'Api::Type::Integer' => 'int',
        'Api::Type::NameValues' => 'dict'
      }.freeze

      include Provider::Ansible::Documentation
      include Provider::Ansible::Module
      include Provider::Ansible::Request
      include Provider::Ansible::SelfLink
      include Provider::Ansible::SubTemplate

      def initialize(config, api, product_folder)
        super(config, api, product_folder)
        @max_columns = 160
      end

      # Returns a string representation of the corresponding Python type
      # for a MM type.
      def python_type(prop)
        prop = Module.const_get(prop).new('') unless prop.is_a?(Api::Type)
        # All ResourceRefs are dicts with properties.
        if prop.is_a? Api::Type::ResourceRef
          return 'str' if prop.resource_ref.virtual
          return 'dict'
        end
        if prop.is_a? Api::Type::Enum
          return PYTHON_TYPE_FROM_MM_TYPE.fetch(prop.element_type, 'str')
        end

        PYTHON_TYPE_FROM_MM_TYPE.fetch(prop.class.to_s, 'str')
      end

      # Returns a unicode formatted, quoted string.
      def unicode_string(string)
        return 'Invalid value' if string.nil?
        return "u#{quote_string(string)}" unless string.include? 'u\''
      end

      def self_link_url(resource)
        (product_url, resource_url) = self_link_raw_url(resource)
        full_url = [product_url, resource_url].flatten.join
        # Double {} replaced with single {} to support Python string
        # interpolation
        "#{full_url.gsub('{{', '{').gsub('}}', '}')}"
      end

      def collection_url(resource)
        base_url = resource.base_url.split("\n").map(&:strip).compact
        full_url = [resource.__product.default_version.base_url,
                    base_url].flatten.join
        # Double {} replaced with single {} to support Python string
        # interpolation
        "#{full_url.gsub('{{', '{').gsub('}}', '}')}"
      end

      def list_url(resource)
        op = resource.apis["list"]
        v = []
        unless op.query_params.nil?
          op.identity.each do |i|
            if op.query_params.include?(i)
              v << i
            end
          end

          if v.count != op.identity.count
            ["marker", "limit", "offset"].each do |i|
              if op.query_params.include?(i)
                v << i
              end
            end
          end
        end

        base_url = op.path
        unless v.empty?
          base_url = base_url + "?" + v.map { |i| "#{i}={#{i}}" }.join("&")
        end
        full_url = [resource.__product.default_version.base_url,
                    base_url].flatten.join
        # Double {} replaced with single {} to support Python string
        # interpolation
        "#{full_url.gsub('{{', '{').gsub('}}', '}')}"
      end

      def async_operation_url(resource, url)
        base_url = resource.__product.default_version.base_url
        url = [base_url, url].join
        "#{url.gsub('{{', '{').gsub('}}', '}')}"
      end

      # Returns the name of the module according to Ansible naming standards.
      # Example: hwc_dns_managed_zone
      def module_name(object)
        ["%s_#{object.__product.prefix[1..-1]}" % @api.cloud_short_name,
         Google::StringUtils.underscore(object.name)].join('_')
      end

      def build_object_data(object, output_folder)
        # Method is overriden to add Ansible example objects to the data object.
        data = super

        prod_name = Google::StringUtils.underscore(data[:object].name)
        path = File.join(@product_folder, "examples/ansible/#{prod_name}.yaml")

        data.merge(example: (get_example(path) if File.file?(path)))
      end

      # Given a URL and function name, emit a URL.
      # URL functions will have 1-3 parameters.
      # * module will always be included.
      # * extra_data is a dict of extra information.
      # * extra_url will have a URL chunk to be appended after the URL.
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def emit_link(name, url, object, has_extra_data = false, service_type='', is_class_method=false)
        params = emit_link_var_args(url, has_extra_data, is_class_method)
        extra = (' + extra_url' if url.include?('<|extra|>')) || ''
        session = is_class_method ? "self.session" : "session"
        md = is_class_method ? "self.module" : "session.module"
        if rrefs_in_link(url, object)
          url_code = "#{url}.format(**res)#{extra}"
          [
            "@link_wrapper",
            "def #{name}(#{params.join(', ')}):",
            indent("res = #{resourceref_hash_for_links(url, object)}", 4),
            indent("return #{url_code}", 4).gsub('<|extra|>', '')
          ].join("\n")
        elsif has_extra_data
          [
            "@link_wrapper",
            "def #{name}(#{params.join(', ')}):",
            indent([
                     ("url = \"#{url}#{extra}\"".gsub('<|extra|>', '') if url.start_with?("http")),
                     ("url = \"{endpoint}#{url}#{extra}\"".gsub('<|extra|>', '') unless url.start_with?("http")),
                     "\n",
                   ].compact, 4),
            indent([
                     "combined = #{md}.params.copy()",
                     'if extra_data:',
                     indent('combined.update(extra_data)', 4),
                     "\n",
                     (send_request("combined['project'] = #{session}.get_project_id()", "", md) if url.include?("{project}")),
                     ("\n" if url.include?("{project}")),
                     ("combined['parent_id'] = #{md}.params['id']" if url.include?("{parent_id}")),
                     (send_request("combined['endpoint'] = #{session}.get_service_endpoint(\'#{service_type}\')", "", md) unless url.start_with?("http")),
                     "\n",
                   ].compact, 4),
            indent('return url.format(**combined)', 4),
          ].compact.join("\n")
        else
          need_combined = url.include?("{project}") || url.include?("{parent_id}") || (not url.start_with?("http"))
          [
            "@link_wrapper",
            "def #{name}(#{params.join(', ')}):",
            indent([
                     ("url = \"#{url}#{extra}\"".gsub('<|extra|>', '') if url.start_with?("http")),
                     ("url = \"{endpoint}#{url}#{extra}\"".gsub('<|extra|>', '') unless url.start_with?("http")),
                     "\n",
                   ].compact, 4),
            (indent([
                      "combined = #{md}.params.copy()",
                      (send_request("combined['project'] = #{session}.get_project_id()", "", md) if url.include?("{project}")),
                      ("\n" if url.include?("{project}")),
                      ("combined['parent_id'] = #{md}.params['id']" if url.include?("{parent_id}")),
                      (send_request("combined['endpoint'] = #{session}.get_service_endpoint(\'#{service_type}\')", "", md) unless url.start_with?("http")),
                      "\n",
                      "return url.format(**combined)",
                    ].compact, 4) if need_combined),
            (indent("return url.format(**#{md}.params)", 4) unless need_combined),
          ].compact.join("\n")
        end
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      def argu_for_sdkclient(api, is_test=false)
        region = "\"\""
        service_level = "domain"

        if api.service_level == "project"
          region = is_test ? "OS_REGION_NAME" : "get_region(module)"

          service_level = "project"
        end

        sprintf("%s, \"%s\", \"%s\"", region, api.service_type, service_level)
      end

      def ansible_readable_property?(property)
          property.crud.include?("r")
      end

      def has_output_property(property)
        if ansible_readable_property?(property)
          return true
        end

        v = nested_properties(property)
        unless v.nil?
          v.each do |i|
            if has_output_property(i)
              return true
            end
          end
        end

        return false
      end

      def properties_to_show(object)
        object.all_user_properties.select {|p| has_output_property(p)}
      end

      def rrefs_in_link(link, object)
        props_in_link = link.scan(/{([a-z_]*)}/).flatten
        (object.parameters || []).select do |p|
          props_in_link.include?(Google::StringUtils.underscore(p.name)) && \
            p.is_a?(Api::Type::ResourceRef) && !p.resource_ref.virtual
        end.any?
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def resourceref_hash_for_links(link, object)
        props_in_link = link.scan(/{([a-z_]*)}/).flatten
        props = props_in_link.map do |p|
          # Select a resourceref if it exists.
          rref = (object.parameters || []).select do |prop|
            Google::StringUtils.underscore(prop.name) == p && \
              prop.is_a?(Api::Type::ResourceRef) && !prop.resource_ref.virtual
          end
          if rref.any?
            [
              "#{quote_string(p)}:",
              "replace_resource_dict(module.params[#{quote_string(p)}],",
              "#{quote_string(rref[0].imports)})"
            ].join(' ')
          else
            "#{quote_string(p)}: module.params[#{quote_string(p)}]"
          end
        end
        ['{', indent_list(props, 4), '}'].join("\n")
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      def emit_link_var_args(url, extra_data, is_class_method)
        extra_url = url.include?('<|extra|>')
        [
          ('self' if is_class_method),
          ('session' unless is_class_method),
          ("extra_url=''" if extra_url),
          ('extra_data=None' if extra_data)
        ].compact
      end

      # Returns a list of all first-level ResourceRefs that are not virtual
      def nonvirtual_rrefs(object)
        object.all_resourcerefs
              .reject { |prop| prop.resource_ref.virtual }
      end

      # Converts a path in the form a/b/c/d into ['a', 'b', 'c', 'd']
      def path2navigate(path)
        "[#{path.split('/').map { |x| "'#{x}'" }.join(', ')}]"
      end

      # Generates a method declaration with function name `name` and args `args`
      # Arguments may have nils and will be ignored.
      def method_decl(name, args)
        "def #{name}(#{args.compact.join(', ')}):"
      end

      # Generates a method call to function name `name` and args `args`
      # Arguments may have nils and will be ignored.
      def method_call(name, args)
        "#{name}(#{args.compact.join(', ')})"
      end

      # TODO(alexstephen): Standardize on one version and move to provider/core
      # https://github.com/GoogleCloudPlatform/magic-modules/issues/30
      def wrap_field(field, spaces)
        # field.scan goes from 0 -> avail_columns - 1
        # -1 to account for this
        avail_columns = DEFAULT_FORMAT_OPTIONS[:max_columns] - spaces - 1
        field.scan(/\S.{0,#{avail_columns}}\S(?=\s|$)|\S+/)
      end

      def normal_method_name(name)
        name.gsub(/__+|:/, '_')
      end

      private

      def get_example(cfg_file)
        # These examples will have embedded ERB that will be compiled at a later
        # stage.
        ex = Google::YamlValidator.parse(File.read(cfg_file))
        raise "#{cfg_file}(#{ex.class}) is not a Provider::Ansible::Example" \
          unless ex.is_a?(Provider::Ansible::Example)
        ex.validate
        ex
      end

      def generate_resource(data)
        target_folder = data[:output_folder]
        FileUtils.mkpath target_folder
        name = module_name(data[:object])
        generate_resource_file data.clone.merge(
          default_template: 'templates/ansible/resource.erb',
          out_file: File.join(target_folder,
                              "lib/ansible/modules/cloud/" + @api.cloud_half_full_name + "/#{name}.py")
        )
      end

      def example_defaults(data)
        obj_name = Google::StringUtils.underscore(data[:object].name)
        path = ["products/#{data[:product_name]}",
                "examples/ansible/#{obj_name}.yaml"].join('/')

        compile_file(EXAMPLE_DEFAULTS, path) if File.file?(path)
      end

      def generate_resource_tests(data)
        prod_name = Google::StringUtils.underscore(data[:object].name)
        path = File.join(@product_folder, "examples/ansible/#{prod_name}.yaml")

        # Unlike other providers, all resources will not be built at once or
        # in close timing to each other (due to external PRs).
        # This means that examples might not be built out for every resource
        # in a GCP product.
        return unless File.file?(path)

        target_folder = data[:output_folder]
        FileUtils.mkpath target_folder

        name = module_name(data[:object])
        generate_resource_file data.clone.merge(
          default_template: 'templates/ansible/example.erb',
          out_file: File.join(target_folder,
                              "test/integration/targets/#{name}/tasks/main.yml")
        )
      end

      def cloud_name
        @api.cloud_full_name_upper
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
          .gsub(/([a-z\d])([A-Z])/, '\1 \2')
      end

      def custom_override_methods(resource)
        v = @config.overrides.fetch(resource.name, nil)
        return [] if v.nil?

        r = []
        v.properties.each do |_, p|
          if p.is_a?(Provider::Ansible::PropertyOverride)
            r << p.to_request_method
          end
        end

        v.api_parameters.each do |_, p|
          if p.is_a?(Provider::Ansible::PropertyOverride)
            r << p.to_request_method
          end
        end

        v.api_asyncs.each do |_, p|
          if p.is_a?(Provider::AsyncOverride)
            r << p.custom_status_check_func
          end
        end

        r.compact.sort
      end

      def module_import_items(resource)
        v = ["Config", "HwcClientException", "HwcModule", "are_different_dicts",
	     "build_path", "is_empty_value", "navigate_value"]

        resource.apis.each do |_, api|
          unless api.async.nil?
            v << "wait_to_finish"
            break
          end
        end


        resource.apis.each do |_, api|
          if api.service_level.eql?("project")
            v << "get_region"
            break
          end
        end

        if resource.apis["delete"].async.nil? && !resource.apis["create"].async.nil?
          v << "HwcClientException404"
        end

        v = v.sort
        v[-1] = v[-1] + ")"

        r = []
        v1 = []
        pre = ""
        v.each do |i|
          v1 << i
          s = v1.join(", ")
          if s.length > 74
            r << pre + ","
            v1 = [i]
          else
            pre = s
          end
        end

        unless v1.empty?
          r << v1.join(", ")
        end

        indent(r, 4)
      end

      def module_dir
        @api.cloud_half_full_name
      end

      def generate_network_datas(data, object) end

      def generate_base_property(data) end

      def generate_simple_property(type, data) end

      def generate_typed_array(type, data) end

      def emit_nested_object(data) end

      def emit_resourceref_object(data) end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
