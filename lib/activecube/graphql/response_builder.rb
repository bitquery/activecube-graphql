module Activecube::Graphql

  class ResponseBuilder


    class Response

      def initialize row
        @row = row
      end

      def convert_type node_type, value
        case node_type
            when 'Boolean' then
              value==1
            else
              value
        end
      end

    end


    attr_reader :response, :response_class
    def initialize tree, response
      @response = response
      @key_map = Hash[response.columns.map.with_index{|key,index| [key, index]}]
      @response_class = build_response_class tree.root
    end

    def map &block
      raise Activecube::InputArgumentError, "Block expected on map of root response" unless block_given?
      response.rows.map do |row|
        block.call response_class.new row
      end
    end

    def build_response_class from_element

      response_class = Class.new Response

      from_element.children.group_by(&:definition).each{|definition, elements|

        if elements.count==1
          element = elements.first
          if element.children.empty?
            simple_value response_class, definition, element
          elsif element.metric
            array_value response_class, definition, element
          else
            sub_element response_class, definition, element
          end
        else
          match_elements response_class, definition, elements
        end

      }

      response_class

    end

    private

    def match_elements response_class, definition, elements

      index = Hash[elements.collect { |element|
        value = if element.children.empty?
                  [@key_map[element.key], element.context_node.definition.type.name]
                else
                  build_response_class element
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

    def sub_element response_class, definition, element
      subclass = build_response_class element
      response_class.class_eval do
        define_method definition.underscore do |**rest_of_options|
          subclass.new @row
        end
      end
    end

    def node_type element
      element.context_node.definition.type.try(:of_type).try(:name) || element.context_node.definition.type.try(:name)
    end

    def simple_value response_class, definition, element
      index = @key_map[element.key]
      node_type = node_type element
      response_class.class_eval do
        define_method definition.underscore do |**rest_of_options|
          convert_type node_type, @row[index]
        end
      end
    end

    def array_value response_class, definition, element
      index = @key_map[element.key]
      array_element_type = if element.children.empty?
                             node_type element
                           else
                             tuple = element.metric.definition.class.tuple
                             element.children.collect{|a| [ a.name, node_type(a), tuple.index(a.name.to_sym)]  }
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
end
