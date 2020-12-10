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
          @ast_node = context_node.ast_node

          @arguments =  sort_node_arguments ast_node, context_node.arguments.to_h


          if parent
            @definition = context_node.definitions.first.name
            if parent.dimension
              @dimension = parent.dimension
              @field = (parent.field || dimension)[definition.to_sym]
              raise Activecube::InputArgumentError, "#{definition} not implemented for #{key} in cube #{cube.name}" unless @field
            elsif !parent.metric
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

        def sort_node_arguments ast_node, arguments
          if (options = arguments['options']).kind_of?(Hash)
            options_keys = context_node.ast_node.arguments.detect{|x| x.name=='options'}.value.arguments.map{|x|
              x.name.underscore.to_sym
            }
            arguments['options'] = Hash[
                options_keys.collect{|key|
                  raise "Unmatched key #{key}" unless options[key]
                  [key, options[key]]
                }

            ]
          end
          arguments
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

        private

        def apply_args element, args = self.arguments
          args && args.each_pair do |key, value|
            k = key.to_sym
            has_selectors = element.respond_to?(:selectors)
            if has_selectors && k==:any
              element = apply_or_selector element, value
            elsif has_selectors && (selector =  cube.selectors[k])
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
          case method
            when :desc,:asc
              values.collect{|v| KEY_FIELD_PREFIX + v}
            when :limit_by
              values.merge({each: KEY_FIELD_PREFIX + values[:each]})
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

        def apply_or_selector element, value
          selectors = value.collect{|v| make_selector v }.compact
          element.when( Activecube::Query::Selector.or(selectors) )
        end

        def make_selector hash
          raise Activecube::InputArgumentError,  "Hash expected for selector, #{v} found instead" unless hash.kind_of?(Hash)
          selectors = hash.to_a.collect{|attr, expressions|
            k = attr.to_s.camelize(:lower).to_sym
            (expressions.kind_of?(Array) ? expressions : [expressions]).collect{|expression|
              expression.to_a.collect{|c|
                operator, arg  = c
                selector = cube.selectors[k]
                raise Activecube::InputArgumentError, "Selector not found for '#{k}'" unless selector
                raise Activecube::InputArgumentError, "#{selector} does not handle method '#{operator}' '#{k}'" unless selector.respond_to?(operator)
                selector.send(operator, arg) unless arg.nil?
                selector
              }
            }
          }.flatten
          Activecube::Query::Selector.and(selectors)
        end

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