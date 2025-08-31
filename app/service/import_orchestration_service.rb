module Service
  class ImportOrchestrationService
    
    # Resultado estructurado de orquestación
    OrchestrationResult = Struct.new(
      :success?, :result_type, :data, :message, :errors, :metadata, 
      keyword_init: true
    )

    def initialize(file_upload_service, import_use_case, logger = nil)
      @file_upload_service = file_upload_service
      @import_use_case = import_use_case
      @logger = logger || Logger.new(STDOUT)
    end

    # Orquestar importación completa desde upload hasta respuesta
    def orchestrate_import(upload_params)
      temp_file_path = nil
      
      begin
        # 1. Procesar archivo subido
        file_info = @file_upload_service.process_uploaded_file(upload_params)
        temp_file_path = file_info[:temp_file_path]
        
        # 2. Validar archivo para importación
        @file_upload_service.validate_file_for_import(temp_file_path)
        
        # 3. Ejecutar importación
        import_result = @import_use_case.perform(csv_file_path: temp_file_path)
        
        # 4. Preparar resultado de orquestación
        if import_result.success?
          OrchestrationResult.new(
            success?: true,
            result_type: :import_success,
            data: {
              processed_count: import_result.data[:processed_count],
              created_count: import_result.data[:created_count],
              updated_count: import_result.data[:updated_count]
            },
            message: import_result.message,
            metadata: {
              original_filename: file_info[:original_filename],
              file_size: file_info[:file_size],
              import_report: import_result.report
            }
          )
        else
          OrchestrationResult.new(
            success?: false,
            result_type: :import_error,
            data: {
              processed_count: import_result.data&.dig(:processed_count) || 0,
              error_count: import_result.data&.dig(:error_count) || 0
            },
            message: import_result.message,
            errors: extract_import_errors(import_result.report),
            metadata: {
              original_filename: file_info[:original_filename],
              file_size: file_info[:file_size],
              import_report: import_result.report
            }
          )
        end
        
      rescue Service::FileUploadService::FileUploadError => e
        @logger.warn("Error de upload: #{e.message}")
        
        OrchestrationResult.new(
          success?: false,
          result_type: :upload_error,
          message: e.message,
          errors: [{ type: 'file_upload', message: e.message }]
        )
        
      rescue StandardError => e
        @logger.error("Error crítico en orquestación: #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        
        OrchestrationResult.new(
          success?: false,
          result_type: :critical_error,
          message: "Error interno del servidor",
          errors: [{ type: 'internal_error', message: e.message }]
        )
        
      ensure
        # Siempre limpiar archivo temporal
        @file_upload_service.cleanup_temp_file(temp_file_path) if temp_file_path
      end
    end

    # Orquestar preview de importación
    def orchestrate_preview(upload_params, max_rows: 10)
      temp_file_path = nil
      
      begin
        # 1. Procesar archivo subido
        file_info = @file_upload_service.process_uploaded_file(upload_params)
        temp_file_path = file_info[:temp_file_path]
        
        # 2. Validar archivo
        @file_upload_service.validate_file_for_import(temp_file_path)
        
        # 3. Ejecutar preview
        preview_result = @import_use_case.preview(
          csv_file_path: temp_file_path,
          max_preview_rows: max_rows
        )
        
        # 4. Preparar resultado
        if preview_result.success?
          OrchestrationResult.new(
            success?: true,
            result_type: :preview_success,
            data: preview_result.data,
            message: preview_result.message,
            metadata: {
              original_filename: file_info[:original_filename],
              file_size: file_info[:file_size],
              max_rows_analyzed: max_rows
            }
          )
        else
          OrchestrationResult.new(
            success?: false,
            result_type: :preview_error,
            message: preview_result.message,
            errors: [{ type: 'preview_error', message: preview_result.message }],
            metadata: {
              original_filename: file_info[:original_filename],
              file_size: file_info[:file_size]
            }
          )
        end
        
      rescue Service::FileUploadService::FileUploadError => e
        @logger.warn("Error de upload en preview: #{e.message}")
        
        OrchestrationResult.new(
          success?: false,
          result_type: :upload_error,
          message: e.message,
          errors: [{ type: 'file_upload', message: e.message }]
        )
        
      rescue StandardError => e
        @logger.error("Error crítico en preview: #{e.message}")
        
        OrchestrationResult.new(
          success?: false,
          result_type: :critical_error,
          message: "Error interno en preview",
          errors: [{ type: 'internal_error', message: e.message }]
        )
        
      ensure
        @file_upload_service.cleanup_temp_file(temp_file_path) if temp_file_path
      end
    end

    private

    # Extraer errores del reporte de importación de forma estructurada
    def extract_import_errors(import_report)
      return [] unless import_report

      errors = []

      # Errores por tipo
      if import_report[:errors_by_type]
        import_report[:errors_by_type].each do |error_type, count|
          errors << {
            type: 'validation_error',
            error_category: error_type,
            count: count
          }
        end
      end

      # Errores detallados (primeros 5)
      if import_report[:detailed_errors]
        import_report[:detailed_errors].first(5).each do |error_detail|
          errors << {
            type: 'row_error',
            line: error_detail[:line],
            message: error_detail[:error],
            data: error_detail[:data]
          }
        end
      end

      # Error crítico
      if import_report[:critical_error]
        errors << {
          type: 'critical_error',
          message: import_report[:critical_error]
        }
      end

      errors
    end
  end
end
