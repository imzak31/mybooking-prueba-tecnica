require 'securerandom'

module Controller
  module Serializer
    class ImportResultSerializer < BaseSerializer

      # Serializar resultado de importación para respuesta API
      def serialize_import_result(orchestration_result)
        base_response = {
          success: orchestration_result.success?,
          result_type: orchestration_result.result_type,
          message: orchestration_result.message,
          timestamp: Time.now.utc.iso8601
        }

        # Agregar datos específicos según el tipo de resultado
        case orchestration_result.result_type
        when :import_success
          serialize_import_success(base_response, orchestration_result)
        when :import_error
          serialize_import_error(base_response, orchestration_result)
        when :upload_error
          serialize_upload_error(base_response, orchestration_result)
        when :critical_error
          serialize_critical_error(base_response, orchestration_result)
        else
          base_response
        end
      end

      # Serializar resumen ejecutivo para dashboard
      def serialize_import_summary(orchestration_result)
        return {} unless orchestration_result.success?

        data = orchestration_result.data
        metadata = orchestration_result.metadata || {}

        {
          import_summary: {
            file_info: {
              filename: metadata[:original_filename],
              size: format_file_size(metadata[:file_size])
            },
            processing_results: {
              total_processed: data[:processed_count],
              newly_created: data[:created_count],
              updated_existing: data[:updated_count]
            },
            performance: extract_performance_metrics(metadata[:import_report]),
            status: determine_import_status(data)
          }
        }
      end

      private

      # Serializar éxito de importación
      def serialize_import_success(base_response, result)
        base_response.merge({
          data: {
            results: {
              processed_count: result.data[:processed_count],
              created_count: result.data[:created_count],
              updated_count: result.data[:updated_count]
            },
            file_info: {
              filename: result.metadata&.dig(:original_filename),
              size_bytes: result.metadata&.dig(:file_size)
            },
            performance: {
              success_rate: extract_success_rate(result.metadata&.dig(:import_report))
            }
          }
        })
      end

      # Serializar error de importación
      def serialize_import_error(base_response, result)
        import_report = result.metadata&.dig(:import_report)
        
        response_data = {
          data: {
            partial_results: {
              processed_count: result.data[:processed_count],
              error_count: result.data[:error_count]
            },
            file_info: {
              filename: result.metadata&.dig(:original_filename)
            }
          },
          errors: serialize_errors(result.errors)
        }
        
        # Agregar reporte detallado si está disponible
        if import_report
          response_data[:report] = {
            summary: import_report[:summary],
            errors_by_type: import_report[:errors_by_type],
            detailed_errors: import_report[:detailed_errors]&.map do |error|
              {
                line: error[:line],
                error: error[:error],
                error_type: error[:error_type],
                data: error[:data],
                suggestions: error[:suggestions]
              }
            end
          }
          
          response_data[:error_summary] = build_error_summary_from_report(import_report)
          response_data[:troubleshooting] = generate_troubleshooting_from_report(import_report)
        else
          response_data[:error_summary] = build_error_summary(result.errors)
          response_data[:troubleshooting] = generate_troubleshooting_tips(result.errors)
        end
        
        base_response.merge(response_data)
      end

      # Construir resumen de errores desde reporte de importación
      def build_error_summary_from_report(import_report)
        summary = import_report[:summary] || {}
        errors_by_type = import_report[:errors_by_type] || {}
        
        most_common_error = errors_by_type.max_by { |_type, count| count }&.first
        
        {
          total_error_types: errors_by_type.keys.length,
          total_affected_rows: summary[:failed_rows] || 0,
          most_common_error: most_common_error,
          success_rate: summary[:success_rate] || 0,
          error_distribution: errors_by_type
        }
      end

      # Generar troubleshooting desde reporte de importación
      def generate_troubleshooting_from_report(import_report)
        tips = []
        errors_by_type = import_report[:errors_by_type] || {}
        
        if errors_by_type['PriceDefinitionNotFoundError'] || errors_by_type.any? { |type, _| type.include?('DefinitionNotFound') }
          tips << "Verificar que las categorías, sucursales y tipos de tarifa existan en el sistema"
          tips << "Crear las definiciones de precio faltantes en CategoryRentalLocationRateType"
        end
        
        if errors_by_type['InvalidSeasonError']
          tips << "Verificar nombres de temporadas en el CSV"
          tips << "Comprobar que las temporadas pertenezcan al SeasonDefinition correcto"
        end
        
        if errors_by_type['InvalidUnitsError']
          tips << "Revisar que las unidades estén permitidas en units_management_value_days_list"
          tips << "Verificar rangos permitidos para cada PriceDefinition"
        end
        
        if tips.empty?
          tips << "Revisar formato de datos en el CSV"
          tips << "Contactar soporte técnico si persisten los problemas"
        end
        
        {
          suggested_actions: tips,
          error_types_found: errors_by_type.keys,
          documentation_link: "/docs/import-troubleshooting"
        }
      end

      # Serializar error de upload
      def serialize_upload_error(base_response, result)
        base_response.merge({
          error_category: 'file_upload',
          errors: serialize_errors(result.errors),
          troubleshooting: {
            common_causes: [
              "Verificar que el archivo sea un CSV válido",
              "Comprobar que el tamaño no exceda 10MB",
              "Asegurar que el archivo no esté corrupto"
            ]
          }
        })
      end

      # Serializar error crítico
      def serialize_critical_error(base_response, result)
        base_response.merge({
          error_category: 'internal_server_error',
          errors: serialize_errors(result.errors),
          support_info: {
            error_id: generate_error_id,
            contact: "Contactar al equipo de desarrollo con este ID"
          }
        })
      end

      # Serializar lista de errores
      def serialize_errors(errors)
        return [] unless errors

        errors.map do |error|
          serialized_error = {
            type: error[:type],
            message: error[:message]
          }

          # Agregar campos específicos según el tipo
          case error[:type]
          when 'validation_error'
            serialized_error[:category] = error[:error_category]
            serialized_error[:count] = error[:count]
          when 'row_error'
            serialized_error[:line] = error[:line]
            serialized_error[:data] = error[:data] if error[:data]
          end

          serialized_error
        end
      end

      # Construir resumen de errores
      def build_error_summary(errors)
        return {} unless errors

        validation_errors = errors.select { |e| e[:type] == 'validation_error' }
        row_errors = errors.select { |e| e[:type] == 'row_error' }

        {
          total_error_types: validation_errors.length,
          total_affected_rows: row_errors.length,
          most_common_error: find_most_common_error(validation_errors)
        }
      end

      # Generar tips de troubleshooting
      def generate_troubleshooting_tips(errors)
        return [] unless errors

        tips = []
        error_types = errors.map { |e| e[:type] }.uniq

        if error_types.include?('validation_error')
          tips << "Verificar que las categorías, sucursales y tipos de tarifa existan en el sistema"
          tips << "Comprobar que las temporadas sean válidas para cada definición de precio"
        end

        if error_types.include?('row_error')
          tips << "Revisar el formato de las columnas requeridas"
          tips << "Asegurar que los precios sean números válidos"
        end

        tips
      end

      # Extraer tasa de éxito
      def extract_success_rate(import_report)
        return 0 unless import_report&.dig(:summary)
        
        import_report[:summary][:success_rate] || 0
      end

      # Extraer métricas de performance
      def extract_performance_metrics(import_report)
        return {} unless import_report&.dig(:summary)

        {
          total_rows: import_report[:summary][:total_rows],
          success_rate: import_report[:summary][:success_rate],
          processing_time: import_report[:timestamp]
        }
      end

      # Determinar estatus general de importación
      def determine_import_status(data)
        total = data[:processed_count] || 0
        created = data[:created_count] || 0
        updated = data[:updated_count] || 0

        if total == 0
          'no_data_processed'
        elsif created > updated
          'primarily_new_data'
        elsif updated > created
          'primarily_updates'
        else
          'mixed_operations'
        end
      end

      # Encontrar error más común
      def find_most_common_error(validation_errors)
        return nil if validation_errors.empty?

        validation_errors.max_by { |e| e[:count] || 0 }&.dig(:error_category)
      end

      # Formatear tamaño de archivo
      def format_file_size(size_bytes)
        return 'Unknown' unless size_bytes

        units = %w[B KB MB GB]
        unit_index = 0
        size = size_bytes.to_f

        while size >= 1024 && unit_index < units.length - 1
          size /= 1024
          unit_index += 1
        end

        "#{size.round(2)} #{units[unit_index]}"
      end

      # Generar ID único para errores críticos
      def generate_error_id
        "ERR_#{Time.now.to_i}_#{SecureRandom.hex(4).upcase}"
      end
    end
  end
end
