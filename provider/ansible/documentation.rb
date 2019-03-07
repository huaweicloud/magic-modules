# 2018.05.31 - changed method of 'autogen_notice_contrib'
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
require 'compile/core'
require 'provider/config'
require 'provider/core'
require 'provider/ansible/manifest'

module Provider
  module Ansible
    # Responsible for building out YAML documentation blocks.
    # rubocop:disable Metrics/ModuleLength
    module Documentation
      # This is not a comprehensive list of unsafe characters.
      # Ansible's YAML linter is more forgiving than Ruby's.
      # A more restricted list of unsafe characters allows for more
      # human readable YAML.
      UNSAFE_CHARS = %w[: & #].freeze
      # Takes a long string and divides each string into multiple paragraphs,
      # where each paragraph is a properly indented multi-line bullet point.
      #
      # Example:
      #   - This is a paragraph
      #     that wraps under
      #     the bullet properly
      #   - This is the second
      #     paragraph.
      def bullet_lines(line, spaces)
        line.split(".\n").map { |paragraph| bullet_line(paragraph, spaces) }
      end

      def bullet_lines1(line, spaces)
        line.split(/^\n/).map { |paragraph| bullet_line1(paragraph, spaces) }
      end

      # Takes in a string (representing a paragraph) and returns a multi-line
      # string, where each line is less than max_length characters long and all
      # subsequent lines are indented in by spaces characters
      #
      # Example:
      #   - This is a sentence
      #     that wraps under
      #     the bullet properly
      #
      #   - |
      #     This is a sentence
      #     that wraps under
      #     the bullet properly
      #     because of the :
      #     character
      # rubocop:disable Metrics/AbcSize
      def bullet_line(paragraph, spaces, _multiline = true, add_period = true)
        paragraph += '.' unless paragraph.end_with?('.') || !add_period
        paragraph = format_url(paragraph)
        paragraph = paragraph.tr("\n", ' ').strip

        # Paragraph placed inside array to get bullet point.
        yaml = [paragraph].to_yaml
        # YAML documentation header is not necessary.
        yaml = yaml.gsub("---\n", '') if yaml.include?("---\n")

        # YAML dumper isn't very smart about line lengths.
        # If any line is over 160 characters (with indents), build the YAML
        # block using wrap_field.
        # Using YAML.dump output ensures that all character escaping done
        if yaml.split("\n").any? { |line| line.length > (160 - spaces) }
          return wrap_field(
            yaml.tr("\n", ' ').gsub(/\s+/, ' '),
            spaces + 3
          ).each_with_index.map { |x, i| i.zero? ? x : indent(x, 2) }
        end
        yaml
      end

      def bullet_line1(paragraph, spaces)
        paragraph = paragraph.tr("\n", ' ').strip
        paragraph += '.' unless paragraph.end_with?('.')

        spaces += 2
        line_len = 79 - spaces
        if line_len < 20
            line_len = 20
        end

        s1 = paragraph
        r = []
        while s1.length > line_len do
            # +1, because maybe the s1[line_len] == ' '
            i = s1.rindex(' ', line_len)
            if i.nil?
              s2 = s1[0, line_len]
              s1 = s1[line_len..-1]
            else
              s2 = s1[0, i]
              s1 = s1[(i + 1)..-1]
            end
            r << "  %s\n" % s2
        end
        unless s1.empty?
            r << "  %s\n" % s1
        end

        r[0] = "- %s\n" % r[0].strip
        r.join
      end

      # rubocop:enable Metrics/AbcSize

      # Builds out a full YAML block for DOCUMENTATION
      # This includes the YAML for the property as well as any nested props
      def doc_property_yaml(prop, object, spaces)
        return if prop.crud.eql?("r")
        block = minimal_doc_block(prop, object, spaces)
        # Ansible linter does not support nesting options this deep.
        if prop.is_a?(Api::Type::NestedObject)
          block.concat(nested_doc(prop.properties, object, spaces))
        elsif prop.is_a?(Api::Type::Array) &&
              prop.item_type.is_a?(Api::Type::NestedObject)
          block.concat(nested_doc(prop.item_type.properties, object, spaces))
        else
          block
        end
      end

      # Builds out a full YAML block for RETURNS
      # This includes the YAML for the property as well as any nested props
      def return_property_yaml(prop, spaces)
        block = minimal_return_block(prop, spaces)
        if prop.is_a? Api::Type::NestedObject
          block.concat(nested_return(prop.properties, spaces))
        elsif prop.is_a?(Api::Type::Array) &&
              prop.item_type.is_a?(Api::Type::NestedObject)
          block.concat(nested_return(prop.item_type.properties, spaces))
        else
          block
        end
      end

      private

      # Find URLs and surround with U()
      def format_url(paragraph)
        paragraph.gsub(%r{
          https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]
          [a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+
          [a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))
          [a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9]\.[^\s]{2,}
        }x, 'U(\\0)')
      end

      # Returns formatted nested documentation for a set of properties.
      def nested_return(properties, spaces)
        block = [indent('contains:', 4)]
        block.concat(
          properties.map do |p|
            indent(return_property_yaml(p, spaces + 8), 8)
          end
        )
      end

      def nested_doc(properties, object, spaces)
        block = [indent('suboptions:', 4)]
        block.concat(
          properties.map do |p|
            indent(doc_property_yaml(p, object, spaces + 8), 8)
          end
        )
      end

      # Builds out the minimal YAML block for DOCUMENTATION
      def minimal_doc_block(prop, _object, spaces)
        [
          minimal_yaml(prop, spaces),
          indent([
            "required: #{prop.required ? 'true' : 'false'}",
            ('type: bool' if prop.is_a? Api::Type::Boolean),
            ("aliases: [#{prop.aliases.join(', ')}]" if prop.aliases),
            (if prop.is_a? Api::Type::Enum
               if prop.element_type.nil? || prop.element_type == 'Api::Type::String'
                 [
                   'choices:',
                   "[#{prop.values.map { |x| quote_string(x.to_s) }.join(', ')}]"
                 ].join(' ')
               else
                 [
                   'choices:',
                   "[#{prop.values.map { |x| x.to_s }.join(', ')}]"
                 ].join(' ')
               end
             end)
          ].compact, 4)
        ]
      end
      # rubocop:enable Metrics/AbcSize

      # Builds out the minimal YAML block for RETURNS
      def minimal_return_block(prop, spaces)
        type = python_type(prop)
        # Complex types only mentioned in reference to RETURNS YAML block
        # Complex types are nested objects traditionally, but arrays of nested
        # objects will be included to avoid linting errors.
        type = 'complex' if prop.is_a?(Api::Type::NestedObject) \
                            || (prop.is_a?(Api::Type::Array) \
                            && prop.item_type.is_a?(Api::Type::NestedObject))
        [
          minimal_yaml(prop, spaces),
          indent([
                   'returned: success',
                   "type: #{type}"
                 ], 4)
        ]
      end

      # Builds out the minimal YAML block necessary for a property.
      # This block will need to have additional information appened
      # at the end.
      def minimal_yaml(prop, spaces)
        [
          "#{Google::StringUtils.underscore(prop.name)}:",
          indent(
            [
              'description:',
              # + 8 to compensate for name + description.
              indent(
                bullet_lines1(convert_underscores(prop.description),
                              spaces + 8),
                4)
            ], 4
          )
        ]
      end

      def autogen_notice_contrib
        ['Please read more about how to change this file at',
         'https://www.github.com/huaweicloud/magic-modules']
      end

      def convert_underscores(desc)
        def f(s)
          i = s.index('_')
          g1 = i == 1 ? ' C(' : s[0] + 'C('
          g2 = s[-1] == ')' ? ')' : ')' + s[-1]
          g1 + '_' + g2
        end

        desc.gsub(/(?: |[^C]\()(_)(?: |,|\))/) {|s| f(s)}
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
