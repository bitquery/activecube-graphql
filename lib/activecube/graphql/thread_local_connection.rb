require "active_record"

module Activecube
  module Graphql
    # Соединение ClickHouse на время резолва одного поля.
    #
    # Rails 6.0 connected_to(database:) переустанавливает пул модели в общем
    # для процесса ConnectionHandler (remove_connection → disconnect! → новый
    # пул), и параллельные поля бьют друг друга. Подменять ConnectionHandler
    # целиком тоже нельзя: в том же потоке модели других баз (справочник
    # Blockchain на ReferenceRecord) перестают находить свои пулы.
    #
    # Поэтому глобальное состояние не трогается вовсе: для поля создаётся
    # собственный ConnectionPool по конфигу базы и кладётся в thread-local.
    # connection/connection_pool на ActiveRecord::Base отдают его тем классам,
    # чьё connection_specification_name совпадает с именем пула (ровно те,
    # кому прежде пул переустанавливал connected_to; приложение зовёт и
    # ActiveRecord::Base.connection напрямую). Остальные — как раньше. Пул
    # отключается по окончании поля.
    module ThreadLocalConnection
      KEY = :activecube_graphql_pool

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
        install
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
