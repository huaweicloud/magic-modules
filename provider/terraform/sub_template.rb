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

module Provider
  class Terraform < Provider::AbstractCore
    # Functions to compile sub-templates.
    module SubTemplate
      def build_schema_property(property, object)
        compile_template'templates/terraform/schema_property.erb',
                        property: property,
                        object: object
      end

      # Transforms a Cloud API representation of a property into a Terraform
      # schema representation.
      def build_flatten_method(prefix, property)
        compile_template 'templates/terraform/flatten_parameter_method.erb',
                         prefix: prefix,
                         property: property
      end

      # Transforms a Terraform schema representation of a property into a
      # representation used by the Cloud API.
      def build_expand_method(resource, op, prefix, property)
        compile_template 'templates/terraform/expand_parameter_method.erb',
                         resource: resource,
                         op: op,
                         prefix: prefix,
                         property: property
      end

      def build_expand_properties(resource, properties, op, args, prefix, map_obj, return_value)
        compile_template 'templates/terraform/expand_properties.erb',
                         resource: resource,
                         properties: properties,
                         op: op,
                         args: args,
                         prefix: prefix,
                         map_obj: map_obj,
                         return_value: return_value
      end

      def build_expand_resource_ref(var_name, property)
        compile_template 'templates/terraform/expand_resource_ref.erb',
                         var_name: var_name,
                         property: property
      end

      def build_property_documentation(property)
        compile_template 'templates/terraform/property_documentation.erb',
                         property: property
      end

      def build_nested_property_documentation(property)
        compile_template(
          'templates/terraform/nested_property_documentation.erb',
          property: property
        )
      end

      def build_async_wait_method(async, status, return_v, timeout, client)
        compile_template 'templates/terraform/async_wait_method.erb',
                         async: async,
                         status: status,
                         return_v: return_v,
                         timeout: timeout,
                         client: client
      end

      def build_resource_async_op(api, timeout, resource_name)
        compile_template 'templates/terraform/async_wait.erb',
                         api: api,
                         timeout: timeout,
                         resource_name: resource_name
      end

      def build_action_method(resource, resource_name, api)
        compile_template 'templates/terraform/action.erb',
                         resource: resource,
                         resource_name: resource_name,
                         api: api
      end

      def build_other_r_method(resource_name, api)
        compile_template 'templates/terraform/other_r.erb',
                         resource_name: resource_name,
                         api: api
      end

      def build_other_cu_method(resource, prefix, resource_name, api)
        compile_template 'templates/terraform/other_cu.erb',
                         resource: resource,
                         prefix: prefix,
                         resource_name: resource_name,
                         api: api
      end

      private

      def autogen_notice_contrib
        ['Please read more about how to change this file at',
         'https://www.github.com/huaweicloud/magic-modules']
      end

      def autogen_notice_text(line)
        line&.empty? ? '//' : "// #{line}"
      end

      def compile_template(template_file, data)
        ctx = binding
        data.each { |name, value| ctx.local_variable_set(name, value) }
        compile_file(ctx, template_file).join("\n")
      end
    end
  end
end
