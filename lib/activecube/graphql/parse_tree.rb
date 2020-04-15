module Activecube
  module Graphql
    class ParseTree

      class Element

        TYPENAME = '__typename'
        KEY_FIELD_PREFIX = '_aq.'

        attr_reader :arguments, :ast_node, :cube, :parent, :name, :definition, :key,
                    :children, :metric, :dimension, :field, :context_node
        def initialize cube, context_node, parent = nil

          @cube = cube
          @parent = parent

          @name = context_node.name
          @key = parent ? (parent.key ? "#{parent.key}.#{name}" : KEY_FIELD_PREFIX+name ) : nil

          @context_node = context_node
          @arguments =  context_node.arguments.to_h

          @ast_node = context_node.ast_node

          if parent
            @definition = context_node.definitions.first.name
            if parent.dimension
              @dimension = parent.dimension
              @field = (parent.field || dimension)[definition.to_sym]
              raise Activecube::InputArgumentError, "#{definition} not implemented for #{key} in cube #{cube.name}" unless @field
            elsif parent.metric
              raise Activecube::InputArgumentError, "Unexpected metric #{key} in cube #{cube.name}"
            else
              if !(@metric = (cube.metrics && cube.metrics[definition.to_sym])) && !(@dimension = (cube.dimensions && cube.dimensions[definition.to_sym]))
                raise Activecube::InputArgumentError, "Metric or dimension #{definition} for #{key} not defined for cube #{cube.name}"
              end
            end
          end

          @children = context_node.typed_children.values.map(&:values).flatten.uniq(&:name).
              select{|child| child.name!=TYPENAME || union? }.
              collect do |child|
            Element.new cube, child, self
          end

        end

        def union?
          context_node.return_type.kind_of? GraphQL::UnionType
        end

        def append_query query
          if parent

            if metric
              query = query.measure({key => apply_args(metric)})
            elsif dimension
              if children.empty?
                query = query.slice({key => apply_args(field || dimension)})
              elsif !arguments.empty?
                query = apply_args query
              end
            end

          else
            query = apply_args query, ( arguments && arguments.except('options'))
            query = apply_args query, ( arguments && arguments['options'] )
          end

          children.each do |child|
            query = child.append_query query
          end

          query
        end

        def apply_args element, args = self.arguments
          args && args.each_pair do |key, value|
            k = key.to_sym
            if element.respond_to?(:selectors) && (selector =  cube.selectors[k])
              if value.kind_of? Hash
                element = apply_selector element, k, value
              elsif value.kind_of? Array
                element = apply_to_array(element, k, selector, value)
              elsif !value.nil?
                element = element.when( selector.eq(value) )
              end
            elsif element.respond_to? k
              element = element.send(k, *converted_field_array(k, value))
            else
              raise Activecube::InputArgumentError, "Field #{k} is not implemented for #{element}"
            end

          end
          element
        end

        def converted_field_array method, values
          if [:desc,:asc].include?(method)
            values.collect{|v| KEY_FIELD_PREFIX + v}
          else
            values
          end
        end

        def apply_selector element, k, hash
          hash.each_pair do |operator, arg|
            selector = cube.selectors[k]
            raise Activecube::InputArgumentError, "#{selector} does not handle method '#{operator}' for #{element} '#{k}'" unless selector.respond_to?(operator)
            element = element.when( selector.send(operator, arg) ) unless arg.nil?
          end
          element
        end

        private

        def apply_to_array(element, k, selector, value)

          if !value.detect { |e| !e.kind_of? Hash }
            value.each { |v|
              element = apply_selector element, k, v
            }
          else
            element = element.when(selector.in(value))
          end
          element
        end

      end

      attr_reader :root, :cube
      def initialize cube, context_node
        @cube = cube
        @root = Element.new cube, context_node
      end

      def build_query
        root.append_query cube
      end

    end
  end
end