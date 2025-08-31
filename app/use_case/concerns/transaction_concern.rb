module UseCase
  module Concerns
    module TransactionConcern
      extend ActiveSupport::Concern

      # Errores específicos de transacciones
      class TransactionError < StandardError; end
      class RollbackRequiredError < TransactionError; end

      # Ejecutar bloque dentro de transacción con manejo de errores robusto
      def with_transaction(isolation_level: :default, &block)
        begin
          Infraestructure::Transaction.within_transaction(isolation_level) do |transaction|
            result = yield transaction
            
            # Si el resultado indica que se requiere rollback, ejecutarlo
            if should_rollback?(result)
              transaction.rollback
              raise RollbackRequiredError, "Transacción cancelada por lógica de negocio"
            end
            
            result
          end
        rescue RollbackRequiredError => e
          # Re-lanzar errores de rollback intencional
          raise e
        rescue StandardError => e
          # Log de errores de transacción
          log_transaction_error(e)
          raise TransactionError, "Error en transacción: #{e.message}"
        end
      end

      # Ejecutar operación con reintentos en caso de deadlock
      def with_retry_on_deadlock(max_retries: 3, &block)
        retries = 0
        
        begin
          yield
        rescue => e
          if deadlock_error?(e) && retries < max_retries
            retries += 1
            sleep(0.1 * retries) # Backoff exponencial
            retry
          else
            raise e
          end
        end
      end

      # Ejecutar operación batch con transacciones por lotes
      def with_batch_transaction(items, batch_size: 100, &block)
        results = []
        errors = []
        
        items.each_slice(batch_size).with_index do |batch, batch_index|
          begin
            batch_results = with_transaction do |transaction|
              batch.map.with_index do |item, item_index|
                begin
                  yield item, batch_index, item_index
                rescue StandardError => e
                  # Capturar errores individuales pero continuar con el batch
                  error_info = {
                    batch: batch_index,
                    item_index: item_index,
                    item: item,
                    error: e.message
                  }
                  errors << error_info
                  nil
                end
              end.compact
            end
            
            results.concat(batch_results)
            
          rescue TransactionError => e
            # Si falla el batch completo, registrar error por cada item
            batch.each_with_index do |item, item_index|
              errors << {
                batch: batch_index,
                item_index: item_index,
                item: item,
                error: "Batch failed: #{e.message}"
              }
            end
          end
        end
        
        {
          results: results,
          errors: errors,
          success_count: results.length,
          error_count: errors.length
        }
      end

      private

      # Determinar si se debe hacer rollback basado en el resultado
      def should_rollback?(result)
        return false unless result.respond_to?(:dig) || result.respond_to?(:[])
        
        # Si el resultado tiene un flag explícito de rollback
        return true if result.is_a?(Hash) && result[:rollback_required]
        
        # Si es un resultado de importación con demasiados errores
        if result.respond_to?(:error_count) && result.respond_to?(:processed_count)
          total = result.error_count + result.processed_count
          return total > 0 && (result.error_count.to_f / total) > 0.5
        end
        
        false
      end

      # Detectar errores de deadlock específicos de MySQL
      def deadlock_error?(error)
        error.message.include?('Deadlock found') ||
        error.message.include?('Lock wait timeout') ||
        error.message.include?('deadlock')
      end

      # Log estructurado de errores de transacción
      def log_transaction_error(error)
        logger&.error("Transaction error: #{error.class.name} - #{error.message}")
        logger&.error("Backtrace: #{error.backtrace.first(5).join("\n")}")
      end

      # Obtener logger del contexto actual
      def logger
        @logger || Rails.logger
      end
    end
  end
end
