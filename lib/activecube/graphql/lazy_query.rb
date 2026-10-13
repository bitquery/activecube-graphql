require 'concurrent'
require "activecube/graphql/thread_local_connection"

module Activecube
  module Graphql
    # Отложенное значение поля куба.
    #
    # Запрос к ClickHouse стартует СРАЗУ при резолве поля, а значение отдаётся
    # по требованию. graphql-ruby форсирует lazy-значения только после того, как
    # зарезолвит все соседние поля уровня, поэтому несколько алиасов одного
    # корневого поля уходят в базу одновременно, и время запроса становится
    # max(A, B) вместо A + B.
    #
    # Соединение берётся из пула ActiveRecord, а он потредовый — каждый поток
    # получает своё, поэтому состояние адаптера (@stat/@headers/@session_id
    # в with_statistics) не разделяется. Общий объект Statistics безопасен:
    # единственная запись в нём идемпотентна, а query_id генерируется свой
    # на каждый вызов query_settings.
    class LazyQuery
      # Сколько запросов одного GraphQL-запроса разрешено держать в полёте.
      # Пул ActiveRecord для clickhouse по умолчанию 5 на процесс, Puma в проде
      # запущена с одним потоком на воркер (RAILS_MAX_THREADS=1), поэтому 4
      # оставляет соединение в запасе.
      #
      # 0 или 1 выключает параллельность полностью — аварийный тормоз без
      # передеплоя кода.
      DEFAULT_MAX_PARALLEL = 4

      def self.max_parallel
        @max_parallel ||= begin
          value = ENV['ACTIVECUBE_PARALLEL_FIELDS']
          value.nil? ? DEFAULT_MAX_PARALLEL : value.to_i
        end
      end

      def self.reset_max_parallel!
        @max_parallel = nil
      end

      def self.semaphore
        @semaphore ||= Concurrent::Semaphore.new([max_parallel, 1].max)
      end

      # on_force — вызывается в форсирующем потоке после завершения фонового
      # блока (см. CubeField: повторное connected_to ради вложенных резолверов).
      # При синхронном вычислении не вызывается: блок сам отработал в этом потоке.
      # parallel: false — блок будет вычислен синхронно при форсировании
      # (прежнее поведение); см. CubeField#parallel_safe?.
      def initialize(on_force: nil, parallel: true, &block)
        @block = block
        @on_force = on_force
        @thread = parallel ? start_thread : nil
      end

      # Форсирование значения. Исключения, пойманные в потоке, поднимаются здесь,
      # чтобы обработка ошибок осталась такой же, как при синхронном резолве.
      def value
        return @value if defined?(@value)

        if @thread
          outcome = @thread.value
          @on_force.call if @on_force
        else
          outcome = run_block
        end
        @value = unwrap(outcome)
      end

      private

      # Если параллельность выключена или свободных разрешений нет — считаем
      # синхронно в вызывающем потоке. Это ровно прежнее поведение, то есть
      # деградация безопасная.
      def start_thread
        return nil if self.class.max_parallel <= 1
        return nil unless self.class.semaphore.try_acquire

        Thread.new do
          begin
            Thread.current.report_on_exception = false
            Thread.current[ThreadLocalConnection::FIELD_THREAD] = true
            with_rails_executor { run_block }
          ensure
            self.class.semaphore.release
          end
        end
      end

      def run_block
        @block.call
      rescue Exception => ex # rubocop:disable Lint/RescueException
        ex
      end

      def with_rails_executor
        if defined?(::Rails) && ::Rails.application
          # Отдаёт соединение ActiveRecord в пул по выходу из блока, иначе
          # поток утащил бы его с собой.
          ::Rails.application.executor.wrap { yield }
        else
          yield
        end
      end

      # Преобразование доменных ошибок в GraphQL::ExecutionError — забота
      # вызывающего блока (там известно имя куба). Здесь только поднимаем то,
      # что поймали в потоке, как есть.
      def unwrap(outcome)
        raise outcome if outcome.is_a?(Exception)

        outcome
      end
    end
  end
end
