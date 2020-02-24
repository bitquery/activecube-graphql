module Activecube::Graphql

  class ResponseBuilder


    class Response

      def initialize row
        @row = row
      end

    end


    attr_reader :response, :response_class
    def initialize tree, response
      @response = response
      @key_map = Hash[response.columns.map.with_index{|key,index| [key, index]}]
      @response_class = build_response_class tree.root
    end

    def map &block
      raise ArgumentError, "Block expected on map of root response" unless block_given?
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
                  @key_map[element.key]
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
          elsif value.kind_of? Integer
            @row[value]
          else
            raise ArgumentError, "Unexpected request to #{definition} by key #{key}"
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

    def simple_value response_class, definition, element
      index = @key_map[element.key]
      response_class.class_eval do
        define_method definition.underscore do |**rest_of_options|
          @row[index]
        end
      end
    end



  end
end