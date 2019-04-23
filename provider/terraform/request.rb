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

require 'provider/abstract_core'

module Provider
  class Terraform < Provider::AbstractCore
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
          indent, true
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

      def convert_custom_method(p, f, fn)
        if p.is_a? Api::Type::NestedObject || p.is_a?(Api::Type::Array)
          return f.gsub(/{class}\(/, fn + '(')
        end
        f
      end

      private

      def request_property(prop, hash_name='', module_name='', invoker='')
        fn = prop.field

        return [fn, request_output(prop, hash_name, module_name, invoker)].flatten
      end

      def response_property(prop, hash_name='', prefix='', invoker='')
        return response_output(prop, hash_name, prefix, invoker)
      end

      # rubocop:disable Metrics/MethodLength
      def response_output(prop, hash_name, prefix, invoker='')
        fn = prop.field

        if prop.from_response
          return fn, "flatten#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        elsif prop.is_a? Api::Type::NestedObject
          return fn, "flatten#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return fn, "flatten#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        # elsif prop.is_a?(Api::Type::Integer)
        #   return fn, "convertToInt(#{hash_name})", true

        else
          return fn, hash_name, false
        end
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def request_output(prop, hash_name, prefix, invoker='')
        if prop.to_request
          return "expand#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        elsif prop.is_a? Api::Type::NestedObject
          return "expand#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return "expand#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        elsif prop.is_a?(Api::Type::NameValues)
          return "expand#{prefix}#{titlelize(prop.name)}(#{hash_name})", true

        else
          return hash_name, false
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

      def convert_parameter(prop, arguments, prefix)
        f = "expand#{prefix}#{titlelize(prop.name)}(#{arguments})"

        if prop.to_request
          return f

        elsif prop.to_request_method
          return sprintf("%s(%s)", prop.to_request_method, arguments)

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
          i = "[]string{#{index2navigate(prop.field, true)}}"
          return "navigateValue(#{d}, #{i}, #{ai})"
        end
      end

      def convert_resp_parameter(prop, arguments, prefix, first_assign, parent_var, set_to, resource_name)
        return first_assign, "" unless has_output_property(prop)

        read_err = sprintf("fmt.Errorf(\"Error reading %s:%s, err: %%s\", err)", resource_name, prop.out_name)
        prop_var = "#{go_variable(prop.name)}Prop"

        set_to_schema = indent([
          "if err != nil {\nreturn #{read_err}\n}",
           sprintf("if err = d.Set(\"%s\", %s); err != nil {", prop.out_name, prop_var),
           sprintf("return fmt.Errorf(\"Error setting %s:%s, err: %%s\", err)\n}", resource_name, prop.out_name),
        ], 4)

        set_to_parent = indent([
          "if err != nil {\nreturn nil, #{read_err}\n}",
          sprintf("%s[\"%s\"] = %s", parent_var, prop.out_name, prop_var),
        ], 4)

        f = indent([
          sprintf("%s, _ := %s[\"%s\"]", prop_var, parent_var, prop.out_name),
          sprintf("%s, err %s flatten%s%s(%s, %s)", prop_var, first_assign ? ":=" : "=", prefix, titlelize(prop.name), arguments, prop_var),
          (set_to.eql?("parent") ? set_to_parent : set_to_schema),
        ].compact.flatten, 4)


        if prop.from_response
          return false, f

        elsif prop.is_a? Api::Type::NestedObject
          return false,  f

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return false,  f

        elsif prop.is_a?(Api::Type::NameValues)
          return false,  f

        else
          i = "[]string{#{index2navigate(prop.field, false)}}"
          v = arguments.split(", ")

          return false, indent([
            sprintf("%s, err := navigateValue(%s, %s, %s)", prop_var, v[0], i, v[1]),
            (set_to.eql?("parent") ? set_to_parent : set_to_schema),
          ].compact.flatten, 4)
        end
      end

      def build_list_query_params(api, spaces)
        page = []
        identity = []
        api.query_params.each do |i|
          case i
          when "limit"
            page << "limit=10"
          when "offset"
            page << "offset=%v"
          when "start"
            page << "start=%v"
          when "marker"
            page << "marker=%v"
          else
            identity << i if api.identity.has_key?(i)
          end
        end

        if identity.empty?
          page.empty? ? "" : indent(sprintf("queryLink := \"?%s\"", page.join("&")), spaces)
        else
          out = []
          if identity.length == 1
            k = identity[0]
            if k.eql?("id")
              out << sprintf("queryLink := \"?%s%s=\" + identity[\"id\"].(string)", page.empty? ? "" : page.join("&") + "&", k)
            else
              out << "\nv, err := convertToStr(identity[\"#{k}\"])\nif err != nil{\nreturn nil, err\n}"
              out << sprintf("queryLink := \"?%s%s=\" + v", page.empty? ? "" : page.join("&") + "&", k)
            end
          else
            out << "p := make([]string, 0, #{identity.length})"
            identity.each do |k|
              out << "if v, err := convertToStr(identity[\"#{k}\"]); err == nil{\np = append(p, fmt.Sprintf(\"#{k}=%v\", v))\n} else {\nreturn nil, err\n}"
            end
            out << sprintf("queryLink := \"?%s\" + strings.Join(p, \"&\")", page.empty? ? "" : page.join("&") + "&")
          end
          indent(out, spaces)
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
