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

module Api
  # Represents an asynchronous operation definition
  class Async < Api::Object
    attr_reader :operation
    attr_reader :result
    attr_reader :status
    attr_reader :error
    attr_reader :async_methods
    attr_reader :timeout

    def validate
      super

      check_property :operation, Operation

      # for delete, the custom status method is generated, no need config.
      check_optional_property :status, Status
      check_optional_property :error, Error
      check_optional_property :update_status, Status
      check_optional_property :aync_methods, Array
      check_optional_property :result, Result # not all async operations have result

      @timeout ||= 10 * 60
      check_optional_property :timeout, Integer
    end

    def update_status
      @update_status || @status
    end

    # Represents the operations (requests) issues to watch for completion
    class Operation < Api::Object
      attr_reader :path
      attr_reader :base_url
      attr_reader :wait_ms
      attr_reader :service_type

      def validate
        super
        check_property :base_url, String

        check_optional_property :path, Hash
	if @path
          @path.each {|k, v| check_property_value("async.operation.path:#{k}", v, String)}
	end

	@wait_ms ||= 1000
        check_optional_property :wait_ms, Integer

	check_optional_property :service_type, String
      end
    end

    # Represents the results of an Operation request
    class Result < Api::Object
      attr_reader :path # used to navigate the original resource id
      attr_reader :base_url #not used, delete later
      def validate
        super
        check_property :path, String
	check_optional_property :base_url, String
      end
    end

    # Provides information to parse the result response to check operation
    # status
    class Status < Api::Object
      attr_reader :path
      attr_reader :complete
      attr_reader :allowed
      attr_reader :custom_function

      def validate
        super
        check_property :path, String
        check_property :complete, Array
        check_optional_property :allowed, Array
        check_optional_property :custom_function, String
      end
    end

    # Provides information on how to retrieve errors of the executed operations
    class Error < Api::Object
      attr_reader :path
      attr_reader :message

      def validate
        super
        check_property :path, String
        check_property :message, String
      end
    end
  end
end
