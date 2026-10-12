require "activecube/graphql/parse_tree"
require "activecube/graphql/response_builder"
require "activecube/graphql/lazy_query"
require "activecube/graphql/field_stats"
require "active_record"
require "securerandom"

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

        object = obj.object
        database = (object.kind_of?(Hash) && object[:database]) ||
          (object.respond_to?(:database) && object.database)

        cube_name = cube.name

        # Возвращаем отложенное значение: запрос к базе стартует сразу, а
        # graphql-ruby форсирует результат только после резолва всех соседних
        # полей. Благодаря этому алиасы одного корневого поля идут в базу
        # одновременно. Требует lazy_resolve(LazyQuery, :value) на схеме.
        LazyQuery.new do
          begin
            response = database ? with_isolated_connection(database) do
              execute_query(tree, ctx, object)
            end : execute_query(tree, ctx, object)

            ResponseBuilder.new tree, response
          rescue Activecube::InputArgumentError => ex
            raise GraphQL::ExecutionError, "Error executing #{cube_name}: #{ex.message}"
          end
        end
      end

      private

      # Rails 6.0: cube.connected_to(database:) переустанавливает пул "primary"
      # в ConnectionHandler, общем для всех потоков процесса
      # (remove_connection → disconnect! → новый пул). Два параллельных поля
      # на одной базе бьют друг друга: пока один поток находится между
      # удалением старого пула и вставкой нового, второй в
      # retrieve_connection_pool проваливается в пул процесса-прародителя
      # (мастер Puma) с конфигом без database и падает с
      # "No database specified". Поэтому каждому полю — собственный
      # ConnectionHandler, подменённый в thread-local только на время запроса;
      # общий handler процесса при этом не трогается вовсе.
      def with_isolated_connection(database)
        model = cube.send(:super_model)
        handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
        handler.establish_connection(model.send(:resolve_config_for_connection, database))
        model.send(:swap_connection_handler, handler) { yield }
      ensure
        handler.clear_all_connections! if handler
      end

      def execute_query tree, ctx, object
        cube_query = tree.build_query
        cube_query = object.append_cube_query(cube_query) if object.respond_to?(:append_cube_query)
        cube_query.stats = field_stats(ctx)
        cube_query.headers = ctx[:headers]
        cube_query.query
      end

      # Своя сессия ClickHouse на каждое поле (см. FieldStats). Суффикс —
      # путь поля в ответе: уникален в пределах запроса и виден в query_log.
      def field_stats ctx
        stats = ctx[:stats]
        return stats unless stats.respond_to?(:session_id)

        suffix = ctx.respond_to?(:path) && ctx.path ? ctx.path.join('.') : SecureRandom.hex(4)
        FieldStats.new(stats, suffix)
      end

      def append_extra extra
        unless @extras.include? extra
          @extras << extra
        end
      end

    end
  end
end