module Activecube
  module Graphql
    # cube.database читают модели приложения (QueryHelper.blockchain, селекторы
    # solana/tron/filecoin, coinpath): раньше его выставлял cube.connected_to
    # как @database на классе куба. Для параллельных полей атрибут класса не
    # годится — сестринские поля одного куба могут идти в разные базы
    # (bitcoin(network: litecoin) и bitcoin(network: bitcoin)), поэтому значение
    # на время резолва поля хранится в thread-local, а чтение подменяется на
    # singleton-классе куба. Вне поля (thread-local пуст) — прежнее поведение.
    module ThreadLocalDatabase
      KEY = :activecube_graphql_database

      def database
        Thread.current[KEY] || super
      end

      def self.with(database)
        previous = Thread.current[KEY]
        Thread.current[KEY] = database
        yield
      ensure
        Thread.current[KEY] = previous
      end

      def self.install(cube)
        return unless cube.respond_to?(:singleton_class)
        return if cube.singleton_class.ancestors.include?(self)

        cube.singleton_class.prepend(self)
      end
    end
  end
end
