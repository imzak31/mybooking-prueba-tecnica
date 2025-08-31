module UseCase
  module Concerns
    module LoggingConcern
      extend ActiveSupport::Concern

      # Niveles de log personalizados para el dominio de pricing
      LOG_LEVELS = {
        pricing_import: :info,
        pricing_validation: :debug,
        pricing_error: :error,
        pricing_performance: :info
      }.freeze

      included do
        # Agregar métodos de clase cuando se incluye el concern
      end

      # Log estructurado para eventos de pricing
      def log_pricing_event(event_type, message, details = {})
        log_level = LOG_LEVELS[event_type] || :info
        
        log_entry = {
          timestamp: Time.now.utc.iso8601,
          event_type: event_type,
          message: message,
          context: details.merge(extract_context),
          class: self.class.name
        }

        logger&.send(log_level, format_log_entry(log_entry))
      end

      # Log de performance con medición de tiempo
      def log_with_timing(operation_name, details = {})
        start_time = Time.now
        
        log_pricing_event(:pricing_performance, "Started #{operation_name}", details)
        
        begin
          result = yield
          
          duration = ((Time.now - start_time) * 1000).round(2)
          
          log_pricing_event(
            :pricing_performance, 
            "Completed #{operation_name}", 
            details.merge(duration_ms: duration, success: true)
          )
          
          result
        rescue StandardError => e
          duration = ((Time.now - start_time) * 1000).round(2)
          
          log_pricing_event(
            :pricing_error, 
            "Failed #{operation_name}: #{e.message}", 
            details.merge(duration_ms: duration, error: e.class.name)
          )
          
          raise e
        end
      end

      # Log de validación con contexto detallado
      def log_validation_result(validation_type, success, details = {})
        event_type = success ? :pricing_validation : :pricing_error
        status = success ? "passed" : "failed"
        
        log_pricing_event(
          event_type,
          "Validation #{validation_type} #{status}",
          details.merge(validation_success: success)
        )
      end

      # Log de importación con métricas
      def log_import_progress(processed_count, total_count = nil, details = {})
        progress_info = { processed: processed_count }
        progress_info[:total] = total_count if total_count
        progress_info[:percentage] = ((processed_count.to_f / total_count) * 100).round(2) if total_count && total_count > 0
        
        log_pricing_event(
          :pricing_import,
          "Import progress: #{processed_count}#{total_count ? "/#{total_count}" : ""} rows",
          details.merge(progress_info)
        )
      end

      # Log de métricas de negocio
      def log_business_metrics(metric_type, value, details = {})
        log_pricing_event(
          :pricing_import,
          "Business metric #{metric_type}: #{value}",
          details.merge(metric_type: metric_type, metric_value: value)
        )
      end

      private

      # Extraer contexto automático basado en el objeto actual
      def extract_context
        context = {}
        
        # Si hay un request_id disponible (para web requests)
        context[:request_id] = Thread.current[:request_id] if Thread.current[:request_id]
        
        # Si hay parámetros de usuario disponibles
        context[:user_id] = @current_user&.id if defined?(@current_user) && @current_user
        
        # Información de la clase y método actual
        context[:method] = caller_locations(3, 1)&.first&.label if caller_locations(3, 1)&.first
        
        context
      end

      # Formatear entrada de log para legibilidad
      def format_log_entry(log_entry)
        if logger.respond_to?(:formatter) && logger.formatter.is_a?(Logger::Formatter)
          # Para logs de desarrollo, formato legible
          "#{log_entry[:event_type].upcase} [#{log_entry[:class]}] #{log_entry[:message]} | #{log_entry[:context].to_json}"
        else
          # Para logs de producción, JSON estructurado
          log_entry.to_json
        end
      end

      # Obtener logger del contexto, con fallback
      def logger
        @logger || 
        (defined?(Rails) && Rails.logger) || 
        Logger.new(STDOUT).tap { |l| l.level = Logger::INFO }
      end
    end
  end
end
