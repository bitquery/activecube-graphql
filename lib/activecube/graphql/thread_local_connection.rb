require "active_record"

module Activecube
  module Graphql
    # Соединение ClickHouse на время резолва одного поля в фоновом потоке.
    #
    # Rails 6.0 connected_to(database:) переустанавливает пул "primary" в общем
    # для процесса ConnectionHandler (remove_connection → disconnect! → новый
    # пул). Это не потокобезопасно, но на этом же держится остальное
    # приложение: вложенные резолверы (balances, smartContract и т.п.) идут в
    # ту базу, куда процесс «подключён» последним connected_to, а кубы
    # переопределяют connected_to (ConnectToFlowDatabase → ApplicationRecord
    # .connected_to(database: "<db>_flow")). Поэтому:
    #
    # - в потоке поля (Thread.current[FIELD_THREAD]) connected_to(database:)
    #   на любом классе ActiveRecord не трогает глобальный пул, а создаёт
    #   собственный ConnectionPool в thread-local; connection/connection_pool
    #   отдают его классам с совпадающим connection_specification_name (ровно
    #   тем, кому прежде пул переустанавливал connected_to); остальные
    #   (ReferenceRecord/Blockchain) — как раньше;
    # - вне потока поля connected_to работает как в Rails — см.
    #   CubeField: при форсировании значения в основном потоке он вызывается
    #   ещё раз, чтобы вложенные резолверы видели нужную базу.
    module ThreadLocalConnection
      KEY = :activecube_graphql_pool
      FIELD_THREAD = :activecube_graphql_field_thread

      def connected_to(database: nil, role: nil, prevent_writes: false, &blk)
        return super unless database && Thread.current[FIELD_THREAD]

        database = database.first.last if database.is_a?(Hash)
        Activecube::Graphql::ThreadLocalConnection.with(self, database, &blk)
      end

      def connection
        pool = Activecube::Graphql::ThreadLocalConnection.pool_for(self)
        pool ? pool.connection : super
      end

      def connection_pool
        Activecube::Graphql::ThreadLocalConnection.pool_for(self) || super
      end

      def self.pool_for(klass)
        pool = Thread.current[KEY]
        pool if pool && klass.connection_specification_name == pool.spec.name
      end

      def self.install
        return if ActiveRecord::Base.singleton_class.ancestors.include?(self)

        ActiveRecord::Base.singleton_class.prepend(self)
      end

      def self.with(model, database)
        config = model.send(:resolve_config_for_connection, database)
        resolver = ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(ActiveRecord::Base.configurations)
        pool = ActiveRecord::ConnectionAdapters::ConnectionPool.new(resolver.spec(config))
        previous = Thread.current[KEY]
        Thread.current[KEY] = pool
        yield
      ensure
        Thread.current[KEY] = previous
        pool.disconnect! if pool
      end
    end
  end
end
