module UseCase
  module Pricing
    class ImportPricesUseCase
      include UseCase::Concerns::TransactionConcern
      include UseCase::Concerns::LoggingConcern

      Result = Struct.new(:success?, :authorized?, :data, :message, :report, keyword_init: true)

      def initialize(import_service, logger)
        @import_service = import_service
        @logger = logger
      end

      # Ejecutar importación completa
      def perform(params)
        processed_params = process_params(params)

        # Validar parámetros
        unless processed_params[:valid]
          return Result.new(
            success?: false, 
            authorized?: true, 
            message: processed_params[:message]
          )
        end

        # Validar autorización
        unless processed_params[:authorized]
          return Result.new(
            success?: false, 
            authorized?: false, 
            message: 'No autorizado para importar precios'
          )
        end

        csv_file_path = processed_params[:csv_file_path]
        
        begin
          log_pricing_event(:pricing_import, "Starting price import", { file_path: csv_file_path })

          # Ejecutar importación con medición de tiempo y transacción robusta
          import_result = log_with_timing("price_import_execution") do
            with_retry_on_deadlock(max_retries: 3) do
              with_transaction do |transaction|
                result = @import_service.import_from_csv(csv_file_path)
                
                # Si hay demasiados errores, hacer rollback
                if should_rollback_import?(result)
                  log_pricing_event(
                    :pricing_error, 
                    "Import rollback triggered", 
                    { error_count: result.error_count, total_count: result.processed_count + result.error_count }
                  )
                  
                  return Result.new(
                    success?: false,
                    authorized?: true,
                    message: "Importación cancelada: demasiados errores (#{result.error_count} errores)",
                    report: result.report
                  )
                end
                
                result
              end
            end
          end

          # Log métricas de negocio
          log_business_metrics("prices_imported", import_result.processed_count, { 
            error_count: import_result.error_count,
            file_path: csv_file_path 
          })

          log_pricing_event(
            :pricing_import, 
            "Import completed", 
            { 
              processed: import_result.processed_count, 
              errors: import_result.error_count,
              success: import_result.success?
            }
          )

          # Preparar respuesta basada en resultado
          if import_result.success?
            Result.new(
              success?: true,
              authorized?: true,
              data: {
                processed_count: import_result.processed_count,
                created_count: import_result.report.dig(:summary, :created_prices),
                updated_count: import_result.report.dig(:summary, :updated_prices)
              },
              message: "Importación exitosa: #{import_result.processed_count} precios procesados",
              report: import_result.report
            )
          else
            Result.new(
              success?: false,
              authorized?: true,
              data: {
                processed_count: import_result.processed_count,
                error_count: import_result.error_count
              },
              message: "Importación con errores: #{import_result.error_count} errores encontrados",
              report: import_result.report
            )
          end

        rescue StandardError => e
          log_pricing_event(
            :pricing_error, 
            "Critical import error", 
            { error: e.message, error_class: e.class.name, file_path: csv_file_path }
          )

          Result.new(
            success?: false,
            authorized?: true,
            message: "Error crítico en importación: #{e.message}",
            report: { critical_error: e.message }
          )
        end
      end

      # Preview de importación sin ejecutar
      def preview(params)
        processed_params = process_params(params)

        unless processed_params[:valid]
          return Result.new(
            success?: false, 
            authorized?: true, 
            message: processed_params[:message]
          )
        end

        unless processed_params[:authorized]
          return Result.new(
            success?: false, 
            authorized?: false, 
            message: 'No autorizado para previsualizar importación'
          )
        end

        csv_file_path = processed_params[:csv_file_path]
        max_rows = params[:max_rows] || 10

        begin
          log_pricing_event(:pricing_import, "Starting import preview", { file_path: csv_file_path, max_rows: max_rows })

          preview_result = log_with_timing("import_preview") do
            @import_service.preview_import(csv_file_path, max_rows: max_rows)
          end

          log_pricing_event(
            :pricing_import, 
            "Preview completed", 
            { 
              sample_size: preview_result[:total_sample_size],
              estimated_issues: preview_result[:estimated_issues]
            }
          )

          Result.new(
            success?: true,
            authorized?: true,
            data: preview_result,
            message: "Preview generado exitosamente"
          )

        rescue StandardError => e
          log_pricing_event(
            :pricing_error, 
            "Preview error", 
            { error: e.message, error_class: e.class.name, file_path: csv_file_path }
          )

          Result.new(
            success?: false,
            authorized?: true,
            message: "Error en preview: #{e.message}"
          )
        end
      end

      private

      # Procesar y validar parámetros de entrada
      def process_params(params)
        # Validar parámetros requeridos
        unless params[:csv_file_path]
          return { 
            valid: false, 
            message: 'Ruta del archivo CSV es requerida' 
          }
        end

        csv_file_path = params[:csv_file_path]

        # Validar que el archivo existe
        unless File.exist?(csv_file_path)
          return { 
            valid: false, 
            message: "Archivo CSV no encontrado: #{csv_file_path}" 
          }
        end

        # Validar extensión del archivo
        unless csv_file_path.end_with?('.csv')
          return { 
            valid: false, 
            message: 'El archivo debe tener extensión .csv' 
          }
        end

        # Validar tamaño del archivo (límite de 10MB para seguridad)
        file_size = File.size(csv_file_path)
        max_size = 10 * 1024 * 1024 # 10MB

        if file_size > max_size
          return { 
            valid: false, 
            message: "Archivo demasiado grande: #{file_size} bytes. Máximo permitido: #{max_size} bytes" 
          }
        end

        # TODO: Implementar validación de autorización real
        # Por ahora, siempre autorizado para la prueba técnica
        authorized = true

        {
          valid: true,
          authorized: authorized,
          csv_file_path: csv_file_path,
          max_preview_rows: params[:max_preview_rows]
        }
      end

      # Determinar si se debe hacer rollback de la importación
      def should_rollback_import?(import_result)
        return false if import_result.error_count == 0

        total_rows = import_result.processed_count + import_result.error_count
        error_rate = import_result.error_count.to_f / total_rows

        # Rollback si más del 50% de las filas tienen errores
        error_rate > 0.5
      end
    end
  end
end
