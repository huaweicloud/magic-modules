# 2018.11.23 add a new method of substitute_tf_var, and remove unused methods
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

require 'uri'
require 'api/object'
require 'compile/core'
require 'google/golang_utils'
require 'provider/abstract_core'
require 'provider/property_override'

module Provider
  class Terraform < Provider::AbstractCore

    # Generates configs to be shown as examples in docs and outputted as tests
    # from a shared template
    class Example < Api::Object
      include Compile::Core

      # product_dir/examples/terraform/{{name}}.tf
      # in this file, if you want to add a random string to a resource name,
      # use the replace holder of 'env-val'; if you want to use the global
      # environment name, use the replaceholder of 'env-' + real env name,
      # like 'env-OS_NETWORK_ID'
      attr_reader :name

      # The id of the "primary" resource in an example. For example:
      # resource "huaweicloud_compute_instance_v2" {{primary_resource_id}} {
      #   ...
      # }
      attr_reader :primary_resource_id

      # it stands for that this example is basic usage and there is only one
      # basic example for each resource
      attr_reader :is_basic

      def config_documentation
        body = lines(compile_file(
                       {
                         vars: vars,
                         primary_resource_id: primary_resource_id,
                         version: version
                       },
                       "templates/terraform/examples/#{name}.tf.erb"
        ))
        lines(compile_file(
                { content: body },
                'templates/terraform/examples/base_configs/documentation.tf.erb'
        ))
      end

      def config_test(product_dir)
        body = lines(compile_file(
          {
            primary_resource_id: primary_resource_id,
          },
          product_dir + "examples/terraform/#{name}.tf"
        ))

        substitute_tf_var body
      end

      def config_example
        @vars ||= []
        body = lines(compile_file(
                       {
                         vars: vars.map { |k, str| [k, "#{str}-${local.name_suffix}"] }.to_h,
                         primary_resource_id: primary_resource_id,
                         version: version
                       },
                       "templates/terraform/examples/#{name}.tf.erb"
        ))

        substitute_example_paths body
      end

      def substitute_tf_var(tf)
        gv = tf.scan(/env-OS_[A-Z_]+/)
        iv = tf.enum_for(:scan, /(?=_env-val)/).map { Regexp.last_match.offset(0).first }
        ig = tf.enum_for(:scan, /(?=env-OS_[A-Z_]+)/).map { Regexp.last_match.offset(0).first }

        r = []
        iv.each_index do |i|
          r << [iv[i], "val"]
        end
        ig.each_index do |i|
         r << [ig[i], gv[i].sub("env-", "")]
        end
	r1 = []
        r.sort { |x, y| x[0] <=> y[0] }.each { |i| r1 << i[1]}

        s = tf.gsub(/env-OS_[A-Z_]+/, "%s")
        s = s.gsub(/_env-val/, "%s")
        lines([
          " return fmt.Sprintf(`",
          s[0..-2],
          "\t`, " + r1.join(', ') + ")"
        ])
      end

      def validate
        super

        check_property :name, String
        check_property :primary_resource_id, String
        check_optional_property :is_basic, :boolean
      end
    end
  end
end
