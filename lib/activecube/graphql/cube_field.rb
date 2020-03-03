require "activecube/graphql/parse_tree"
require "activecube/graphql/response_builder"

require "graphql/schema/member"
require "graphql/schema/field_extension"
require "graphql/schema/field"
require "graphql/schema/argument"
require "graphql/execution/errors"


module Activecube
  module Graphql
    class CubeField <  GraphQL::Schema::Field
      argument_class GraphQL::Schema::Argument

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
          execute_query(tree, ctx)
        end : execute_query(tree, ctx)

        if ctx[:stat_io].respond_to?(:puts) && response.respond_to?(:statistics)
          ctx[:stat_io].puts(response.statistics)
        end

        ResponseBuilder.new tree, response

      rescue ArgumentError => ex
         raise GraphQL::ExecutionError, "Error executing #{cube.name}: #{ex.message}"
      end

      private

      def execute_query tree, ctx
        cube_query = tree.build_query
        ctx[:sql_io].puts(cube_query.to_sql) if ctx[:sql_io].respond_to?(:puts)
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