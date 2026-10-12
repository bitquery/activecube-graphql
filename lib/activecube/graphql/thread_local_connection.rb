require "active_record"

module Activecube
  module Graphql
    # Соединение ClickHouse на время резолва одного поля.
    #
    # Rails 6.0 connected_to(database:) переустанавливает пул "primary" в общем
    # для процесса ConnectionHandler (remove_connection → disconnect! → новый
    # пул), и параллельные поля бьют друг друга. Подменять ConnectionHandler
    # целиком тоже нельзя: в том же потоке модели других баз (справочник
    # Blockchain на ReferenceRecord) перестают находить свои пулы.
    #
    # Поэтому глобальное состояние не трогается вовсе: для поля создаётся
    # собственный ConnectionPool по конфигу базы, кладётся в thread-local, а
    # `connection` у модели куба (и её наследников) читает его первым. Пул
    # отключается по окончании поля.
    module ThreadLocalConnection
      KEY = :activecube_graphql_pool

      def connection
        pool = Thread.current[KEY]
        pool ? pool.connection : super
      end

      def self.install(model)
        return if model.singleton_class.ancestors.include?(self)

        model.singleton_class.prepend(self)
      end

      def self.with(model, database)
        install(model)
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
