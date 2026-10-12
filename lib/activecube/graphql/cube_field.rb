require "activecube/graphql/parse_tree"
require "activecube/graphql/response_builder"
require "activecube/graphql/lazy_query"
require "activecube/graphql/field_stats"
require "activecube/graphql/thread_local_database"
require "activecube/graphql/thread_local_connection"
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
        ThreadLocalDatabase.install(cube) if cube
        # Pass on the default args:
        super(*args, **kwargs, &block)
        append_extra :irep_node
      end

      def resolve_field_method(obj, ruby_kwargs, ctx)

        return super unless cube

        irep_node = ruby_kwargs[:irep_node]
        tree = ParseTree.new cube, irep_node
        # Сигнатура execute_query(tree, ctx, object) — публичный контракт:
        # приложение её переопределяет (prepend) и зовёт super, поэтому
        # статистика поля передаётся через tree, а не аргументом.
        tree.stats = field_stats ctx, irep_node

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
            ThreadLocalDatabase.with(database) do
              response = database ? with_isolated_connection(database) do
                execute_query(tree, ctx, object)
              end : execute_query(tree, ctx, object)

              ResponseBuilder.new tree, response
            end
          rescue Activecube::InputArgumentError => ex
            raise GraphQL::ExecutionError, "Error executing #{cube_name}: #{ex.message}"
          end
        end
      end

      private

      # Соединение ClickHouse — своё на поле, без правки глобального состояния
      # (см. ThreadLocalConnection). cube.connected_to не используется: его
      # establish_connection в общем ConnectionHandler не потокобезопасен.
      def with_isolated_connection(database, &block)
        ThreadLocalConnection.with(cube.send(:super_model), database, &block)
      end

      def execute_query tree, ctx, object
        cube_query = tree.build_query
        cube_query = object.append_cube_query(cube_query) if object.respond_to?(:append_cube_query)
        cube_query.stats = tree.stats || ctx[:stats]
        cube_query.headers = ctx[:headers]
        cube_query.query
      end

      # Своя сессия ClickHouse на каждое поле (см. FieldStats). Суффикс —
      # путь поля в ответе (ctx здесь — контекст запроса, его path пуст,
      # поэтому путь собирается по irep_node) плюс случайный хвост на случай
      # одинаковых путей внутри списков.
      def field_stats ctx, irep_node
        stats = ctx[:stats]
        return stats unless stats.respond_to?(:session_id)

        path = []
        node = irep_node
        while node.respond_to?(:name) && node.name
          path.unshift node.name
          node = node.respond_to?(:parent) ? node.parent : nil
        end
        FieldStats.new(stats, "#{path.join('.')}:#{SecureRandom.hex(3)}")
      end

      def append_extra extra
        unless @extras.include? extra
          @extras << extra
        end
      end

    end
  end
end