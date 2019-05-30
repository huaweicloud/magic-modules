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

      def convert_list_api_parameter(resource, prop, arguments, prefix, result_var, spaces)
        r = sprintf("%s[\"%s\"] = ", result_var, prop.name)
        f = [
          sprintf("v = expand_%s_%s(%s)", prefix, prop.out_name, arguments),
          r + "v"
        ]

        if prop.to_request
          return f

        elsif prop.is_a? Api::Type::NestedObject
          return f

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)

          return f unless prop.array_num.nil?

          field = prop.field
          return r + "None" if field.nil? || field.empty?

          p = resource.find_property(field)
          return r + "None" if p.nil? || p.crud.eql?("r")

          return f

        elsif prop.is_a?(Api::Type::NameValues)
          return f

        else
          field = prop.field
          return r + "None" if field.nil? || field.empty?

          p = resource.find_property(field)
          return r + "None" if p.nil? || p.crud.eql?("r")

          d, ai = arguments.split(", ")
          i = "[#{index2navigate(prop.field, true)}]"
          r1 = "v = navigate_value(#{d}, #{i}, #{ai})"
          if r1.length + spaces > 79
            ["v = navigate_value(#{d}, #{i},",
             "                   #{ai})",
             r + "v"
            ]
          else
            [r1,
             r + "v"
            ]
          end
        end
      end

      def convert_parameter(prop, arguments, prefix, spaces)
        f = sprintf("v = expand_%s_%s(%s)", prefix, prop.out_name, arguments)

        if prop.to_request
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
          i = "[#{index2navigate(prop.field, true)}]"
          r = "v = navigate_value(#{d}, #{i}, #{ai})"
          if r.length + spaces > 79
            ["v = navigate_value(#{d}, #{i},",
             "                   #{ai})"
            ]
          else
            r
          end
        end
      end

      def convert_resp_parameter(prop, arguments, prefix, parent_var, spaces)
        unless has_output_property(prop)
          return indent(sprintf("%s.setdefault(\"%s\", None)", parent_var, prop.out_name), spaces)
        end

        prop_var = "v"
        set_parent = sprintf("%s[\"%s\"] = %s", parent_var, prop.out_name, prop_var)

        f = [
          sprintf("%s = %s.get(\"%s\")", prop_var, parent_var, prop.out_name),
          sprintf("%s = flatten%s%s_%s(%s, %s, exclude_output)", prop_var, prefix.empty? ? "" : "_", prefix, prop.out_name, arguments, prop_var),
          set_parent
        ]

        if prop.from_response
          if prop.crud.eql?("r")
            return indent([
              "if not exclude_output:",
              indent(f, 4)
            ], spaces)
          else
            return indent(f, spaces)
          end

        elsif prop.is_a? Api::Type::NestedObject
          if prop.crud.eql?("r")
            return indent([
              "if not exclude_output:",
              indent(f, 4)
            ], spaces)
          else
            return indent(f, spaces)
          end

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          if prop.crud.eql?("r")
            return indent([
              "if not exclude_output:",
              indent(f, 4)
            ], spaces)
          else
            return indent(f, spaces)
          end

        # elsif prop.is_a?(Api::Type::NameValues)
        #   return f

        else
          i = "[#{index2navigate(prop.field, false)}]"
          v = arguments.split(", ")
          len = sprintf("    %s = navigate_value(%s, , %s)", prop_var, v[0], v[1]).length + spaces
          len1 = len - sprintf("%s, , %s)", v[0], v[1]).length - spaces
          if prop.crud.eql?("r")
            indent([
              "if not exclude_output:",
              (sprintf("    %s = navigate_value(%s, %s, %s)", prop_var, v[0], i, v[1]) if i.length <= 79 - len),
              (sprintf("    %s = navigate_value(%s, %s,\n%s%s)", prop_var, v[0], i, ' ' * len1, v[1]) if i.length > 79 - len),
              indent(set_parent, 4),
            ].compact, spaces)
          else
            len -= 4
            len1 -= 4
            indent([
              (sprintf("%s = navigate_value(%s, %s, %s)", prop_var, v[0], i, v[1]) if i.length <= 79 - len),
              (sprintf("%s = navigate_value(%s, %s,\n%s%s)", prop_var, v[0], i, ' ' * len1, v[1]) if i.length > 79 - len),
              set_parent,
            ].compact, spaces)
          end
        end
      end

      def build_list_query_params(api, spaces)
        page = []
        identity = []
        qp = api.query_params || Hash.new
        qp.each do |k, v|
          case k
          when "limit"
            page << "limit=10"
          when "offset"
            page << "offset={offset}"
          when "start"
            page << "start={start}"
          when "marker"
            page << "marker={marker}"
          else
            identity << k
          end
        end

        page_s = page.empty? ? "" : sprintf("%s", page.join("&"))

        if identity.empty?
          page_s.empty? ? "" : indent(sprintf("query_link = \"?%s\"", page_s), spaces)
        else
          out = []
          if identity.length == 1
            k = identity[0]
            out << sprintf("query_link = \"?%s\"", page_s)
            out << sprintf("v = navigate_value(opts, [%s])", index2navigate(qp[k], true))
            out << "if v:"
            out << sprintf("    query_link += \"%s%s=\" + str(v)", page_s.empty? ? "" : "&", k)
          else
            out << "query_params = []"
            identity.each do |k|
              out << sprintf("\nv = navigate_value(opts, [%s])", index2navigate(qp[k], true))
              out << sprintf("if v:\n    query_params.append(\"%s=\" + str(v))", k)
            end
            out << sprintf("\nquery_link = \"?%s\"", page_s)
            out << "if query_params:"
            out << sprintf("    query_link += %s\"&\".join(query_params)", page_s.empty? ? "" : "\"&\" + ", )
          end
          indent(out, spaces)
        end
      end

      def fill_resp_parameter(prop, prefix, parent_var, var, spaces)
        code = indent([
          sprintf("v = fill%s%s_%s(%s.get(\"%s\"))", prefix.empty? ? "" : "_", prefix, prop.out_name, var, prop.name),
          sprintf("%s[\"%s\"] = v", parent_var, prop.name),
        ], spaces)

        if prop.is_a? Api::Type::NestedObject
          return code

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return code

        else
          indent(sprintf("%s[\"%s\"] = %s.get(\"%s\")", parent_var, prop.name, var, prop.name), spaces)
        end
      end

    end
    # rubocop:enable Metrics/ModuleLength
  end
end
