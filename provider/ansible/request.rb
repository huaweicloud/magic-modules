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
        fn = normal_method_name(sprintf("expand_%s_%s", prefix, prop.out_name))
        f = [
          sprintf("v = %s(%s)", fn, arguments),
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

        #elsif prop.is_a?(Api::Type::NameValues)
        #  return f

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
        fn = normal_method_name(sprintf("expand_%s_%s", prefix, prop.out_name))
        f = sprintf("v = %s(%s)", fn, arguments)

        if prop.to_request
          return f

        elsif prop.is_a? Api::Type::NestedObject
          return f

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return f

        #elsif prop.is_a?(Api::Type::NameValues)
        #  return f

        elsif !prop.default.nil?

          if prop.is_a?(Api::Type::String)
            return sprintf("\"%s\"", prop.default)

          elsif prop.is_a?(Api::Type::Boolean)
            return prop.default ? "True" : "False"

          else
            return prop.default.to_i
          end

        else
          raise "no field for parameter: " + prop.name if prop.field.nil?

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

      def _old_version_convert_to_option(prop, arguments, prefix, parent_var, spaces)
        return "" unless has_readable_property(prop)

        prop_var = "v"
        set_parent = sprintf("%s[\"%s\"] = %s", parent_var, prop.out_name, prop_var)

        fn = sprintf("flatten%s%s_%s", prefix.empty? ? "" : "_", prefix, prop.out_name)
        f = [
          sprintf("%s = %s(%s, exclude_output)", prop_var, fn, arguments),
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

      def convert_to_option(prop, arguments, prefix, parent_var, spaces)
        return "" unless has_readable_property(prop)

        prop_var = "v"
        set_parent = sprintf("%s[\"%s\"] = %s", parent_var, prop.out_name, prop_var)

        fn = sprintf("flatten%s%s_%s", prefix.empty? ? "" : "_", prefix, prop.out_name)
        f = [
          sprintf("%s = %s(%s)", prop_var, fn, arguments),
          set_parent
        ]

        if prop.from_response
          return indent(f, spaces)

        elsif prop.is_a? Api::Type::NestedObject
          return indent(f, spaces)

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return indent(f, spaces)

        # elsif prop.is_a?(Api::Type::NameValues)
        #   return f

        else
          i = "[#{index2navigate(prop.field, false)}]"
          v = arguments.split(", ")
          len = sprintf("%s = navigate_value(%s, , %s)", prop_var, v[0], v[1]).length + spaces
          len1 = len - sprintf("%s, , %s)", v[0], v[1]).length - spaces
          indent([
            (sprintf("%s = navigate_value(%s, %s, %s)", prop_var, v[0], i, v[1]) if i.length <= 79 - len),
            (sprintf("%s = navigate_value(\n    %s, %s, %s)", prop_var, v[0], i, v[1]) if i.length > 79 - len),
            set_parent,
          ].compact, spaces)
        end
      end

      def adjust_option(prop, prefix, input_var, cur_var, spaces)
        return "" unless need_adjust_property(prop)

        f = sprintf("%sadjust%s%s_%s(%s, %s)", ' ' * spaces, prefix.empty? ? "" : "_", prefix, prop.out_name, input_var, cur_var)

        if prop.is_a? Api::Type::NestedObject
          return f

        elsif prop.is_a?(Api::Type::Array)
          return f

        end

        raise "impossible to adjust the value of property(#{prop.name})"
      end

      def set_unreadable_option(prop, prefix, input_var, cur_var, spaces)
        return "" unless has_unreadable_property(prop)

        on = prop.out_name

        unless has_readable_property(prop)
          return indent(sprintf("%s[\"%s\"] = %s.get(\"%s\")", cur_var, on, input_var, on), spaces)
        end

        f = sprintf("%sset_unread%s%s_%s(\n%s%s.get(\"%s\"), %s.get(\"%s\"))",
                    ' ' * spaces, prefix.empty? ? "" : "_", prefix, on, ' ' * (spaces + 4), input_var, on, cur_var, on)

        if prop.is_a? Api::Type::NestedObject
          return f

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return f
        end

        raise "impossible to set the unreadable value for property(#{prop.name})"
      end

      def set_readonly_option(prop, prefix, input_var, cur_var, spaces)
        return "" unless has_readonly_property(prop)

        on = prop.out_name

        unless has_unreadonly_property(prop)
          return indent(sprintf("%s[\"%s\"] = %s.get(\"%s\")", input_var, on, cur_var, on), spaces)
        end

        f = sprintf("%sset_readonly%s%s_%s(\n%s%s.get(\"%s\"), %s.get(\"%s\"))",
                    ' ' * spaces, prefix.empty? ? "" : "_", prefix, on, ' ' * (spaces + 4), input_var, on, cur_var, on)

        if prop.is_a? Api::Type::NestedObject
          return f

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return f
        end

        raise "impossible to set the readonly value for property(#{prop.name})"
      end

      def convert_resp_parameter(prop, arguments, prefix, parent_var, spaces)
        unless has_readable_property(prop)
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
        qp = api.query_params || Hash.new
        identity = qp.select { |k, v| !api.known_query_params.include?(k) }
        k, v = api.pagination_param
        page = [
          ("limit=10" if qp.include?("limit")),
          (sprintf("%s={%s}", k, v) unless k.empty?)
        ].compact

        page_s = page.empty? ? "" : sprintf("%s", page.join("&"))

        if identity.empty?
          page_s.empty? ? "" : indent(sprintf("query_link = \"?%s\"", page_s), spaces)
        else
          out = []
          if identity.length == 1
            k = identity.keys()[0]
            v = identity[k]
            out << sprintf("query_link = \"%s\"", page_s.empty? ? "" : "?" + page_s)
            out << sprintf("v = navigate_value(opts, [%s])", index2navigate(v, true))
            out << "if v or v in [False, 0]:"
            out << sprintf("    query_link += \"%s%s=\" + (\n        str(v) if v else str(v).lower())", page_s.empty? ? "?" : "&", k)
          else
            out << "query_params = []"
            identity.each do |k, v|
              out << sprintf("\nv = navigate_value(opts, [%s])", index2navigate(v, true))
              out << sprintf("if v or v in [False, 0]:\n    query_params.append(\n        \"%s=\" + (str(v) if v else str(v).lower()))", k)
            end
            out << sprintf("\nquery_link = \"%s\"", page_s.empty? ? "" : "?" + page_s)
            out << "if query_params:"
            out << sprintf("    query_link += \"%s\" + \"&\".join(query_params)", page_s.empty? ? "?" : "&")
          end
          indent(out, spaces)
        end
      end

      def fill_resp_parameter(prop, prefix, parent_var, var, spaces)
        on = normal_method_name(prop.out_name)

        c = sprintf("v = fill%s%s_%s(%s.get(\"%s\"))", prefix.empty? ? "" : "_", prefix, on, var, prop.name)
        if c.length + spaces > 79
          c = sprintf("v = fill%s%s_%s(\n    %s.get(\"%s\"))", prefix.empty? ? "" : "_", prefix, on, var, prop.name)
        end

        code = indent([
          c,
          sprintf("%s[\"%s\"] = v", parent_var, prop.name),
        ], spaces)

        if prop.is_a? Api::Type::NestedObject
          return code

        elsif prop.is_a?(Api::Type::Array) && \
              prop.item_type.is_a?(Api::Type::NestedObject)
          return code

        else
          c = sprintf("%s[\"%s\"] = %s.get(\"%s\")", parent_var, prop.name, var, prop.name)
          if c.length + spaces > 79
            c = sprintf("%s[\"%s\"] = %s.get(\n    \"%s\")", parent_var, prop.name, var, prop.name)
          end
          indent(c, spaces)
        end
      end

    end
    # rubocop:enable Metrics/ModuleLength
  end
end
