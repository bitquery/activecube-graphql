require 'delegate'

module Activecube
  module Graphql
    # Обёртка над объектом статистики запроса (в приложении —
    # Util::Statistics::Statistics) для одного поля cube. Всё делегируется
    # общему объекту запроса, собственный только session_id.
    #
    # Зачем: session_id уходит в ClickHouse параметром каждого запроса, а по
    # умолчанию равен id GraphQL-запроса — общему для всех полей. Одна сессия
    # ClickHouse не исполняет два запроса одновременно (Code 373 "Session is
    # locked by a concurrent client"), поэтому параллельным полям нужны разные
    # сессии. Явно выставленный session_id= (coinpath, временные таблицы)
    # хранится локально и отдаётся как есть.
    class FieldStats < SimpleDelegator
      def initialize(stats, suffix)
        super(stats)
        @suffix = suffix
        @session_id = nil
      end

      def session_id
        return @session_id if @session_id

        base = __getobj__.session_id
        base ? "#{base}:#{@suffix}" : nil
      end

      def session_id=(value)
        @session_id = value
      end

      def query_settings
        settings = __getobj__.respond_to?(:query_settings) ? __getobj__.query_settings : {}
        settings.merge(session_id: session_id)
      end
    end
  end
end
