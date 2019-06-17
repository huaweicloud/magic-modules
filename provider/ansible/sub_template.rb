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
  module Ansible
    # Functions to compile sub-templates.
    module SubTemplate
      def build_schema_property(property, object)
        compile_template'templates/ansible/schema_property.erb',
                        property: property,
                        object: object
      end

      # Transforms a Cloud API representation of a property into a Terraform
      # schema representation.
      def build_flatten_method(prefix, property)
        compile_template 'templates/ansible/flatten_parameter_method.erb',
                         prefix: prefix,
                         property: property
      end

      def build_update_properties_method(object)
        compile_template 'templates/ansible/update_properties.erb',
                         object: object
      end

      # Transforms a Terraform schema representation of a property into a
      # representation used by the Cloud API.
      def build_expand_method(resource, prefix, property)
        compile_template 'templates/ansible/expand_parameter_method.erb',
                         resource: resource,
                         prefix: prefix,
                         property: property
      end

      def build_expand_properties(properties, args, prefix, map_obj)
        compile_template 'templates/ansible/expand_properties.erb',
                         properties: properties,
                         args: args,
                         prefix: prefix,
                         map_obj: map_obj
      end

      def build_expand_resource_ref(var_name, property)
        compile_template 'templates/ansible/expand_resource_ref.erb',
                         var_name: var_name,
                         property: property
      end

      def build_property_documentation(property)
        compile_template 'templates/ansible/property_documentation.erb',
                         property: property
      end

      def build_nested_property_documentation(property)
        compile_template(
          'templates/ansible/nested_property_documentation.erb',
          property: property
        )
      end

      def build_async_wait_method(async, status, return_v, timeout, client)
        compile_template 'templates/ansible/async_wait_method.erb',
                         async: async,
                         status: status,
                         return_v: return_v,
                         timeout: timeout,
                         client: client
      end

      def build_resource_async_op(api, module_name, gasync=nil)
        compile_template 'templates/ansible/async_wait.erb',
                         module_name: module_name,
                         gasync: gasync,
                         api: api
      end

      def build_action_method(resource, resource_name, api)
        compile_template 'templates/ansible/action.erb',
                         resource: resource,
                         resource_name: resource_name,
                         api: api
      end

      def build_read_method(api, module_name, input_url=false)
        compile_template 'templates/ansible/read_method.erb',
                         module_name: module_name,
                         api: api,
                         input_url: input_url
      end

      def build_send_request_method(api, module_name)
        compile_template 'templates/ansible/send_request.erb',
                         module_name: module_name,
                         api: api
      end

      def build_request_body_method(resource, api)
        compile_template 'templates/ansible/build_request_body.erb',
                         resource: resource,
                         api: api
      end

      def build_fill_resp_body_method(api)
        compile_template 'templates/ansible/fill_resp_body.erb',
                         api: api
      end

      def build_fill_param_method(prefix, property)
        compile_template 'templates/ansible/fill_parameter_method.erb',
                         prefix: prefix,
                         property: property
      end

      def build_identity_object_method(resource, api)
        compile_template 'templates/ansible/build_identity_object.erb',
                         resource: resource,
                         api: api
      end

      def build_expand_list_api_method(resource, prefix, property)
        compile_template 'templates/ansible/expand_list_api_parameter_method.erb',
                         resource: resource,
                         prefix: prefix,
                         property: property
      end

      def build_multi_invoke_method(api, united_async)
        compile_template 'templates/ansible/multi_invoke.erb',
                         united_async: united_async,
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
