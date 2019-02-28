# 2018.05.31 - changed the method of response_output
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

module Provider
  module Ansible
    # Responsible for building out the resource_to_request and
    # request_from_hash methods.
    # rubocop:disable Metrics/ModuleLength
    module Request
      # Takes in a list of properties and outputs a python hash that takes
      # in a module and outputs a formatted JSON request.
      def request_properties(properties, indent = 4, is_in_class = false)
        prefix = is_in_class ? 'self.' : ''
        indent_list(
          properties.map do |prop|
            request_property(prop, "#{prefix}module.params", "#{prefix}module")
          end,
          indent
        )
      end

      def response_properties(properties, indent = 8)
        indent_list(
          properties.map do |prop|
            response_property(prop, 'response', 'module')
          end,
          indent
        )
      end

      def request_properties_in_classes(properties, indent = 4,
                                        hash_name = 'self.request',
                                        module_name = 'self.module')
        indent_list(
          properties.map do |prop|
            request_property(prop, hash_name, module_name, 'self.')
          end,
          indent
        )
      end

      def response_properties_in_classes(properties, indent = 8,
                                         hash_name = 'self.request',
                                         module_name = 'self.module')
        indent_list(
          properties.map do |prop|
            response_property(prop, hash_name, module_name, 'self.')
          end,
          indent
        )
      end

      # This returns a list of properties that require classes being built out.
      def properties_with_classes(properties)
        properties.map do |p|
          if p.is_a? Api::Type::NestedObject
            if need_define_class(p)
              [p] + properties_with_classes(p.properties)
            end
          elsif p.is_a?(Api::Type::Array) && \
                p.item_type.is_a?(Api::Type::NestedObject)
            if need_define_class(p)
              [p] + properties_with_classes(p.item_type.properties)
            end
          end
        end.compact.flatten
      end

      def properties_with_custom_method_for_param(properties)
        properties.map do |p|
          if p.to_request || p.from_response
            [p]
          end
        end.compact.flatten
      end

      def convert_custom_method(p, f)
        if p.is_a? Api::Type::NestedObject || p.is_a?(Api::Type::Array)
          return f.gsub(/{class}\(/, p.property_class[-1] + '(')
        end
        f
      end

      private

      def request_property(prop, hash_name, module_name, invoker='')
        fn = prop.field_name
        fn = fn.include?("/") ? fn[0, fn.index("/")] : fn

        [
          "#{unicode_string(fn)}:",
          request_output(prop, hash_name, module_name, invoker).to_s
        ].join(' ')
      end

      def response_property(prop, hash_name, module_name, invoker='')
        [
          "#{unicode_string(prop.out_name)}:",
          response_output(prop, hash_name, module_name, invoker).to_s
        ].join(' ')
      end

      # rubocop:disable Metrics/MethodLength
      def response_output(prop, hash_name, module_name, invoker='')
        # If input true, treat like request, but use module names.
        return request_output(prop, "#{module_name}.params", module_name) \
          if prop.input
        fn = prop.field_name
        fn = fn.include?("/") ? fn[fn.index("/") + 1..-1] : fn
        if prop.from_response
          [
            "#{invoker}_#{prop.out_name}_convert_from_response(",
            "\n    #{hash_name}.get(#{quote_string(fn)}))",
          ].join
        elsif prop.is_a? Api::Type::NestedObject
          [
            "#{prop.property_class[-1]}(",
            "\n    #{hash_name}.get(#{unicode_string(fn)}, {})",
            ").from_response()"
          ].join
        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          [
            "#{prop.property_class[-1]}(",
            "\n    #{hash_name}.get(#{unicode_string(fn)}, [])",
            ").from_response()"
          ].join
        else
          "#{hash_name}.get(#{unicode_string(fn)})"
        end
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def request_output(prop, hash_name, module_name, invoker='')
        if prop.to_request
          [
            "#{invoker}_#{prop.out_name}_convert_to_request(",
            "#{hash_name}.get(#{quote_string(prop.out_name)}))",
          ].join
        elsif prop.is_a? Api::Type::NestedObject
          [
            "#{prop.property_class[-1]}(",
            "#{hash_name}.get(#{quote_string(prop.out_name)}, {})",
            ").to_request()"
          ].join
        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          [
            "#{prop.property_class[-1]}(",
            "#{hash_name}.get(#{quote_string(prop.out_name)}, [])",
            ").to_request()"
          ].join
        elsif prop.is_a?(Api::Type::ResourceRef) && !prop.resource_ref.virtual
          prop_name = Google::StringUtils.underscore(prop.name)
          [
            "replace_resource_dict(#{hash_name}",
            ".get(#{unicode_string(prop_name)}, {}), ",
            "#{quote_string(prop.imports)})"
          ].join
        elsif prop.is_a?(Api::Type::ResourceRef) && \
              prop.resource_ref.virtual && prop.imports == 'selfLink'
          func_name = Google::StringUtils.underscore("#{prop.name}_selflink")
          [
            "#{func_name}(#{hash_name}.get(#{quote_string(prop.out_name)}),",
            "#{module_name}.params)"
          ].join(' ')
        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::ResourceRef) && \
              !prop.item_type.resource_ref.virtual
          prop_name = Google::StringUtils.underscore(prop.name)
          [
            "replace_resource_dict(#{hash_name}",
            ".get(#{quote_string(prop_name)}, []), ",
            "#{quote_string(prop.item_type.imports)})"
          ].join
        else
          "#{hash_name}.get(#{quote_string(prop.out_name)})"
        end
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def need_define_class(p)
        if p.to_request && p.from_response
          cn = '{class}('
          return p.to_request.include?(cn) || p.from_response.include?(cn)
        end
        true
      end

      def send_request(code, code_if_error = "", module_name = "module", handle_404_code = "")
        [
          "try:",
          indent(code, 4),
          ("except HwcClientException404:" unless handle_404_code.empty?),
          (indent(handle_404_code, 4) unless handle_404_code.empty?),
          "except HwcClientException" + (code_if_error.empty? ? " as ex:" : ":"),
          indent(code_if_error.empty? ? module_name + ".fail_json(msg=str(ex))" : code_if_error, 4),
        ].compact
      end

      def convert_parameter(prop, arguments, prefix, invoker="")
        n = invoker == "Read" ? "flatten" : "expand"
        f = "#{n}_#{prefix}_#{prop.out_name}(#{arguments})"

        if prop.to_request || prop.from_response
          return f

        elsif prop.is_a? Api::Type::NestedObject
          return f

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return f

        elsif prop.is_a?(Api::Type::NameValues)
          return f

        elsif !prop.default.nil?

          if prop.is_a?(Api::Type::String)
            return sprintf("\"%s\"", prop.default)

          elsif prop.is_a?(Api::Type::Boolean)
            return prop.default ? "true" : "false"

          else
            return prop.default.to_i
          end

        else
          d, ai = arguments.split(", ")
          i = "[#{index2navigate(prop.field, invoker != "Read")}]"
          return "navigate_value(#{d}, #{i}, #{ai})"
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
