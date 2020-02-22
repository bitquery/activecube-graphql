require "activecube/graphql/parse_tree"
require "activecube/graphql/response_builder"

module Activecube
  module Graphql
    class CubeField <  GraphQL::Schema::Field
      argument_class Types::BaseArgument

      attr_reader :cube
      # Override #initialize to take a new argument cube:
      def initialize(*args, cube: nil, **kwargs, &block)
        @cube = cube
        # Pass on the default args:
        super(*args, **kwargs, &block)
        append_extra :irep_node
      end

      def resolve_field_method(obj, ruby_kwargs, ctx)

        return super unless cube

        irep_node = ruby_kwargs[:irep_node]
        tree = ParseTree.new cube, irep_node

        database = obj.object.kind_of?(Hash) && obj.object[:database]
        response = database ? cube.connected_to(database: database) do
          execute_query(tree)
        end : execute_query(tree)

        ResponseBuilder.new tree, response

      rescue ArgumentError => ex
         raise GraphQL::ExecutionError, "Error executing #{cube.name}: #{ex.message}"
      end

      private

      def execute_query tree
        cube_query = tree.build_query
        puts cube_query.to_sql
        cube_query.query
      end

      def append_extra extra
        unless @extras.include? extra
          @extras << extra
        end
      end

    end
  end
end