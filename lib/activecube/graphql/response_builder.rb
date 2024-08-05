module Activecube::Graphql

  class ResponseBuilder


    class Response

      def initialize row
        @row = row
      end

      def convert_type type_name, value
        case type_name
            when 'Boolean' then
              value==1
            else
              value
        end
      end

      def __typename
        raise Activecube::InputArgumentError, "Add __typename to the element for UNION or INTERFACE entity to resolve the type"
      end

    end

    class ResponseClassRegistry

      include Singleton

      def initialize
        @registry = {}
      end

      def get_response_class element, key_map
        key = element.to_json + key_map.to_json
        @registry[key] ||= build_response_class(element,key_map)
      end

      def build_response_class from_element, key_map

        response_class = Class.new Response

        from_element.children.group_by(&:definition).each{|definition, elements|

          if elements.count==1
            element = elements.first
            if element.children.empty?
              simple_value response_class, definition, element, key_map
            elsif element.metric
              array_value response_class, definition, element, key_map
            else
              sub_element response_class, definition, element, key_map
            end
          else
            match_elements response_class, definition, elements, key_map
          end

        }

        response_class

      end


      def match_elements response_class, definition, elements, key_map

        index = Hash[elements.collect { |element|
          value = if element.children.empty?
                    [key_map[element.key], element.type_name]
                  else
                    get_response_class element, key_map
                  end
          [element.name, value]
        }]

        response_class.class_eval do
          define_method definition.underscore do |ast_node:, **rest_of_options|
            key = ast_node.alias || ast_node.name
            if (value = index[key]).kind_of? Class
              value.new @row
            elsif value.kind_of? Array
              convert_type value.second, @row[value.first]
            else
              raise Activecube::InputArgumentError, "Unexpected request to #{definition} by key #{key}"
            end
          end
        end

      end

      def sub_element response_class, definition, element, key_map
        subclass = get_response_class element, key_map
        response_class.class_eval do
          define_method definition.underscore do |**rest_of_options|
            subclass.new @row
          end
        end
      end

      def simple_value response_class, definition, element, key_map
        index = key_map[element.key]
        type_name = element.type_name
        response_class.class_eval do
          define_method definition.underscore do |**rest_of_options|
            convert_type type_name, @row[index]
          end
        end
      end

      def array_value response_class, definition, element, key_map
        index = key_map[element.key]
        array_element_type = if element.children.empty?
                               element.type_name
                             else
                               tuple = element.metric.definition.class.tuple
                               element.children.collect{|a| [ a.name, a.type_name, tuple.index(a.name.to_sym)]  }
                             end

        response_class.class_eval do
          define_method definition.underscore do |**rest_of_options|
            @row[index].map{|array_obj|
              if array_obj.kind_of?(Array) && array_element_type.kind_of?(Array)
                Hash[
                  array_element_type.map{|etype|
                    [etype.first.underscore, convert_type(etype.second, array_obj[etype.third])]
                  }]
              elsif !array_obj.kind_of?(Array) && array_element_type.kind_of?(String)
                convert_type(array_element_type, obj)
              else
                raise "Mismatched data in #{array_obj} with #{array_element_type} for #{definition} of #{element.key}"
              end
            }
          end
        end


      end

    end

    attr_reader :response, :response_class
    def initialize tree, response
      @response = response
      key_map = Hash[response.columns.map.with_index{|key,index| [key, index]}]
      @response_class = ResponseClassRegistry.instance.get_response_class tree.root, key_map
    end

    def map &block
      raise Activecube::InputArgumentError, "Block expected on map of root response" unless block_given?
      response.rows.map do |row|
        block.call response_class.new row
      end
    end


  end
end
