module Activecube
  module Graphql
    class ParseTree

      class Element

        attr_reader :arguments, :ast_node, :cube, :parent, :name, :definition, :key,
                    :children, :metric, :dimension, :field
        def initialize cube, context_node, parent = nil

          @cube = cube
          @parent = parent

          @name = context_node.name
          @key = parent ? (parent.key ? "#{parent.key}.#{name}" : name ) : nil

          @arguments =  context_node.arguments.to_h

          @ast_node = context_node.ast_node

          if parent
            @definition = context_node.definitions.first.name
            if parent.dimension
              @field = @definition
            elsif parent.metric
              raise ArgumentError, "Unexpected metric #{key}  for cube #{cube.name}"
            else
              if !(@metric = cube.metrics[definition.to_sym]) && !(@dimension = cube.dimensions[definition.to_sym])
                raise ArgumentError, "Metric or dimension #{definition} for #{key} not defined for cube #{cube.name}"
              end
            end
          end

          @children = context_node.typed_children.values.map(&:values).flatten.collect do |child|
            Element.new cube, child, self
          end

        end


        def append_query query
          if parent

            if metric
              query = measure(metric, query)
            end

            if dimension
              query = slice(dimension, query)
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

        def measure metric, query
          query.measure({key => apply_args(metric)})
        end

        def slice dimension, query
          if children.empty?
            query.slice({key => apply_args(dimension)})
          else
            query.slice Hash[children.collect do |field|
              [field.key, field.apply_args(dimension[field.field.to_sym])]
            end]
          end
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
              element = element.send(k, *value)
            else
              raise ArgumentError, "Field #{k} is not implemented for #{element}"
            end

          end
          element
        end

        def apply_selector element, k, hash
          hash.each_pair do |operator, arg|
            selector = cube.selectors[k]
            raise ArgumentError, "#{selector} does not handle method '#{operator}' for #{element} '#{k}'" unless selector.respond_to?(operator)
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
          elsif !value.detect { |e| !e.kind_of? String }
            element = element.when(selector.in(value))
          else
            raise ArgumentError, "Field #{k} has unexpected array value for #{element}"
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