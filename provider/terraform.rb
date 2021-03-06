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

require 'provider/abstract_core'
require 'provider/terraform/config'
require 'provider/terraform/import'
require 'provider/terraform/custom_code'
require 'provider/terraform/example'
require 'provider/terraform/property_override'
require 'provider/terraform/resource_override'
require 'provider/terraform/request'
require 'provider/terraform/sub_template'
require 'google/golang_utils'

module Provider
  # Code generator for Terraform Resources that manage Google Cloud Platform
  # resources.
  class Terraform < Provider::AbstractCore
    include Provider::Terraform::Import
    include Provider::Terraform::Request
    include Provider::Terraform::SubTemplate
    include Google::GolangUtils

    # Converts between the Magic Modules type of an object and its type in the
    # TF schema
    def tf_types
      {
        Api::Type::Boolean => 'schema.TypeBool',
        Api::Type::Double => 'schema.TypeFloat',
        Api::Type::Integer => 'schema.TypeInt',
        Api::Type::String => 'schema.TypeString',
        # Anonymous string property used in array of strings.
        'Api::Type::String' => 'schema.TypeString',
        Api::Type::Time => 'schema.TypeString',
        Api::Type::Enum => 'schema.TypeString',
        Api::Type::ResourceRef => 'schema.TypeString',
        Api::Type::NestedObject => 'schema.TypeList',
        Api::Type::Array => 'schema.TypeList',
        Api::Type::NameValues => 'schema.TypeMap'
      }
    end

    def optional_compute_forcenew?(property, resource)
      optional = !property.required
      m = {
        "c__"   => [optional, false,    true],
        "_u_"   => [optional, false,    false],
        "__r"   => [false,    true,     false],
        "c_u_"  => [optional, false,    false],
        "c__r"  => [optional, optional, true],
        "_u_r"  => [optional, optional, false],
        "c_u_r" => [optional, optional, false],
      }

      k = ["", "", ""]
      property.crud.each_char do |c|
        case c
        when 'c'
          k[0] = 'c'
        when 'u'
          k[1] = 'u'
        when 'r'
          k[2] = 'r'
        else
          raise "Calc optional_compute_forcenew for property(" + property.out_name + ") :unkonw crud(" + property.crud + ")"
        end
      end

      m[k.join('_')]
    end

    # Transforms a format string with field markers to a regex string with
    # capture groups.
    #
    # For instance,
    #   projects/{{project}}/global/networks/{{name}}
    # is transformed to
    #   projects/(?P<project>[^/]+)/global/networks/(?P<name>[^/]+)
    def format2regex(format)
      format.gsub(/{{([[:word:]]+)}}/, '(?P<\1>[^/]+)')
    end

    # Capitalize the first letter of a property name.
    # E.g. "creationTimestamp" becomes "CreationTimestamp".
    def titlelize(name)
      p = go_variable(name)
      p[0] = p[0].capitalize
      p
    end

    def go_variable(name)
      s = name.gsub(/_(..)_/, &:upcase).gsub(/_(..)$/, &:upcase)
      Google::StringUtils.camelize(s)
    end

    # Filter the properties to keep only the ones requiring custom update
    # method and group them by update url & verb.
    def properties_by_custom_update(properties)
      update_props = properties.reject do |p|
        p.update_url.nil? || p.update_verb.nil?
      end
      update_props.group_by do |p|
        { update_url: p.update_url, update_verb: p.update_verb }
      end
    end

    private

    # This function uses the resource.erb template to create one file
    # per resource. The resource.erb template forms the basis of a single
    # GCP Resource on Terraform.
    def generate_resource(data)
      target_folder = File.join(data[:output_folder], package)
      FileUtils.mkpath target_folder
      name = Google::StringUtils.underscore(data[:object].name)
      version = Google::StringUtils.underscore(data[:object].version)
      version = "_" + version unless version.empty?
      product_name = Google::StringUtils.underscore(data[:product_name])
      filepath = File.join(target_folder, "resource_#{package}_#{product_name}_#{name}#{version}.go")
      generate_resource_file data.clone.merge(
        default_template: 'templates/terraform/resource.erb',
        out_file: filepath
      )
      # TODO: error check goimports
      %x(goimports -w #{filepath})
      %x(gofmt -w #{filepath})

      generate_documentation(data)
    end

    def generate_documentation(data)
      target_folder = data[:output_folder]
      target_folder = File.join(target_folder, 'website', 'docs', 'r')
      FileUtils.mkpath target_folder
      name = Google::StringUtils.underscore(data[:object].name)
      version = Google::StringUtils.underscore(data[:object].version)
      version = "_" + version unless version.empty?
      product_name = Google::StringUtils.underscore(data[:product_name])
      filepath =
        File.join(target_folder, "#{product_name}_#{name}#{version}.html.markdown")
      generate_resource_file data.clone.merge(
        default_template: 'templates/terraform/resource.html.markdown.erb',
        out_file: filepath,
        product_folder: @product_folder
      )
    end

    def package
      @api.cloud_full_name
    end

    def cloud_name
      @api.cloud_full_name_upper
    end

    def async_operation_url(async)
      "#{async.operation.base_url.gsub('{{', '{').gsub('}}', '}')}"
    end

    # Converts a path in the form a/b/c/d into "a", "b", "c", "d"
    def path2navigate(path)
      path.split('/').map { |x| "\"#{x}\"" }.join(', ')
    end

    def nestedobject_properties(obj)
      ps = get_properties(obj)
      if ps.nil?
        return nil
      end

      prefix = obj.is_a?(Api::Type) ? obj.name + "." : ""
      r = Array.new
      ps.each do |item|
        rc = nestedobject_properties(item)
        if rc.nil?
          next
        end

        rc.each do |i|
          r << sprintf("%s%s", prefix, i)
        end
      end

      if obj.is_a?(Api::Type::NestedObject) && (!obj.crud.eql?("r"))
        r << obj.name
      end

      r.empty? ? nil : r
    end

    def generate_resource_tests(data)
      return if data[:object].examples.nil? || data[:object].examples&.select(&:is_basic)&.empty?

      target_folder = File.join(data[:output_folder], package)
      FileUtils.mkpath target_folder
      name = Google::StringUtils.underscore(data[:object].name)
      version = Google::StringUtils.underscore(data[:object].version)
      version = "_" + version unless version.empty?
      product_name = Google::StringUtils.underscore(data[:product_name])
      filepath = File.join(target_folder, "resource_#{package}_#{product_name}_#{name}#{version}_test.go")

      generate_resource_file data.clone.merge(
        default_template: 'templates/terraform/acc_test.go.erb',
        out_file: filepath,
        product_folder: @product_folder
      )
      # TODO: error check goimports
      %x(goimports -w #{filepath})
      %x(gofmt -w #{filepath})

      # import test
      if import_resource?(data[:object])
        filepath = File.join(target_folder, "import_#{package}_#{product_name}_#{name}#{version}_test.go")
        generate_resource_file data.clone.merge(
          default_template: 'templates/terraform/import_test.go.erb',
          out_file: filepath,
          product_folder: @product_folder
        )
        # TODO: error check goimports
        %x(goimports -w #{filepath})
        %x(gofmt -w #{filepath})
      end
    end

    def has_output_property(property)
      if property.crud.include?("r")
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

    # only one case to adjust as bellow
    # 1. the array property that keeps the order of array
    def need_adjust_property(property)
      if property.is_a?(Api::Type::Array) &&
          property.item_type.is_a?(Api::Type::NestedObject) &&
          (!property.identities.nil?) && has_output_property(property)
        return true
      end

      v = property.child_properties
      unless v.nil?
        v.each do |i|
          return true if need_adjust_property(i)
        end
      end

      return false
    end

    def properties_to_show(object)
      object.all_user_properties.select {|p| has_output_property(p)}
    end

    def properties_to_adjust(object)
      object.all_user_properties.select {|p| need_adjust_property(p)}
    end

    def argu_for_sdkclient(api, is_test=false)
      region = "\"\""
      service_level = "serviceDomainLevel"

      if api.service_level == "project"
        region = is_test ? "OS_REGION_NAME" : "GetRegion(d, config)"

        service_level = "serviceProjectLevel"
      end

      sprintf("%s, \"%s\", %s", region, api.service_type, service_level)
    end

    def import_resource?(resource)
      return false # always not generate import relevant codes
      return true unless resource.read_api.nil?

      list_api = resource.list_api
      (list_api.identity.length == 1 && list_api.identity.has_key?("id"))
    end
  end
end
