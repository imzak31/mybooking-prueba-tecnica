module Controller
  module Serializer
    class ImportPreviewSerializer < BaseSerializer

      # Serializar resultado de preview para respuesta API
      def serialize_preview_result(orchestration_result)
        base_response = {
          success: orchestration_result.success?,
          result_type: orchestration_result.result_type,
          message: orchestration_result.message,
          timestamp: Time.now.utc.iso8601
        }

        if orchestration_result.success?
          serialize_preview_success(base_response, orchestration_result)
        else
          serialize_preview_error(base_response, orchestration_result)
        end
      end

      # Serializar análisis detallado para UI avanzada
      def serialize_detailed_analysis(orchestration_result)
        return {} unless orchestration_result.success?

        data = orchestration_result.data
        metadata = orchestration_result.metadata || {}

        {
          file_analysis: {
            file_info: {
              filename: metadata[:original_filename],
              size: format_file_size(metadata[:file_size]),
              analysis_scope: "#{data[:total_sample_size]} rows analyzed"
            },
            feasibility_assessment: {
              estimated_success_rate: calculate_success_rate(data),
              readiness_status: determine_readiness_status(data),
              confidence_level: calculate_confidence_level(data)
            },
            sample_breakdown: serialize_sample_rows(data[:sample_rows]),
            recommendations: generate_recommendations(data)
          }
        }
      end

      # Serializar resumen ejecutivo rápido
      def serialize_quick_summary(orchestration_result)
        return {} unless orchestration_result.success?

        data = orchestration_result.data
        success_rate = calculate_success_rate(data)

        {
          quick_summary: {
            ready_to_import: success_rate >= 95,
            estimated_success_rate: success_rate,
            sample_size: data[:total_sample_size],
            issues_found: data[:estimated_issues],
            recommendation: get_recommendation_by_success_rate(success_rate)
          }
        }
      end

      private

      # Serializar éxito de preview
      def serialize_preview_success(base_response, result)
        data = result.data
        metadata = result.metadata || {}

        base_response.merge({
          data: {
            analysis_summary: {
              sample_size: data[:total_sample_size],
              estimated_issues: data[:estimated_issues],
              estimated_success_rate: calculate_success_rate(data)
            },
            file_info: {
              filename: metadata[:original_filename],
              size_bytes: metadata[:file_size],
              rows_analyzed: metadata[:max_rows_analyzed]
            },
            sample_analysis: serialize_sample_rows(data[:sample_rows]),
            readiness_assessment: {
              status: determine_readiness_status(data),
              recommendations: generate_recommendations(data)
            }
          }
        })
      end

      # Serializar error de preview
      def serialize_preview_error(base_response, result)
        base_response.merge({
          error_category: determine_error_category(result.result_type),
          errors: serialize_errors(result.errors),
          troubleshooting: generate_preview_troubleshooting(result.errors)
        })
      end

      # Serializar filas de muestra
      def serialize_sample_rows(sample_rows)
        return [] unless sample_rows

        sample_rows.map.with_index do |row_result, index|
          {
            row_number: index + 1,
            line_in_file: row_result[:line],
            status: row_result[:success] ? 'valid' : 'invalid',
            analysis: serialize_row_analysis(row_result)
          }
        end
      end

      # Serializar análisis individual de fila
      def serialize_row_analysis(row_result)
        if row_result[:success]
          {
            data_summary: {
              category: row_result.dig(:data, :category_code),
              location: row_result.dig(:data, :rental_location_name),
              rate_type: row_result.dig(:data, :rate_type_name),
              season: row_result.dig(:data, :season_name) || 'No season',
              units: "#{row_result.dig(:data, :units)} #{row_result.dig(:data, :time_measurement)}",
              price: format_price(row_result.dig(:data, :price))
            },
            validation_status: 'passed'
          }
        else
          {
            error_details: {
              message: row_result[:error],
              category: categorize_row_error(row_result[:error])
            },
            validation_status: 'failed'
          }
        end
      end

      # Calcular tasa de éxito estimada
      def calculate_success_rate(data)
        return 0 if data[:total_sample_size] == 0
        
        successful_rows = data[:total_sample_size] - data[:estimated_issues]
        (successful_rows.to_f / data[:total_sample_size] * 100).round(2)
      end

      # Determinar estado de preparación
      def determine_readiness_status(data)
        success_rate = calculate_success_rate(data)
        
        case success_rate
        when 95..100
          'excellent'
        when 80..94
          'good'
        when 60..79
          'fair'
        when 40..59
          'poor'
        else
          'critical'
        end
      end

      # Calcular nivel de confianza
      def calculate_confidence_level(data)
        sample_size = data[:total_sample_size]
        
        case sample_size
        when 0..5
          'low'
        when 6..15
          'medium'
        else
          'high'
        end
      end

      # Generar recomendaciones
      def generate_recommendations(data)
        recommendations = []
        success_rate = calculate_success_rate(data)
        
        case success_rate
        when 95..100
          recommendations << "✅ Archivo listo para importación"
          recommendations << "🚀 Proceder con confianza"
        when 80..94
          recommendations << "⚠️ Revisar errores menores antes de importar"
          recommendations << "📋 Considerar corrección de datos problemáticos"
        when 60..79
          recommendations << "🔧 Corrección de datos recomendada"
          recommendations << "📊 Revisar formato y validaciones"
        when 40..59
          recommendations << "❌ Archivo requiere corrección significativa"
          recommendations << "🔍 Revisar estructura y datos"
        else
          recommendations << "🚫 No proceder con importación"
          recommendations << "📝 Revisar completamente el archivo"
        end
        
        # Recomendaciones específicas basadas en errores
        if data[:sample_rows]
          common_errors = extract_common_error_patterns(data[:sample_rows])
          recommendations.concat(generate_specific_recommendations(common_errors))
        end
        
        recommendations
      end

      # Obtener recomendación por tasa de éxito
      def get_recommendation_by_success_rate(success_rate)
        case success_rate
        when 95..100 then 'proceed_with_import'
        when 80..94 then 'review_and_proceed'
        when 60..79 then 'fix_issues_first'
        else 'major_revision_needed'
        end
      end

      # Determinar categoría de error
      def determine_error_category(result_type)
        case result_type
        when :upload_error then 'file_upload'
        when :preview_error then 'data_analysis'
        when :critical_error then 'system_error'
        else 'unknown'
        end
      end

      # Generar troubleshooting para preview
      def generate_preview_troubleshooting(errors)
        tips = []
        
        errors&.each do |error|
          case error[:type]
          when 'file_upload'
            tips << "Verificar formato CSV y tamaño de archivo"
          when 'preview_error'
            tips << "Comprobar estructura de columnas"
          when 'internal_error'
            tips << "Contactar soporte técnico"
          end
        end
        
        tips.uniq
      end

      # Categorizar error de fila
      def categorize_row_error(error_message)
        case error_message.downcase
        when /campo requerido/
          'missing_required_field'
        when /formato.*precio/
          'invalid_price_format'
        when /no se encontró.*definición/
          'price_definition_not_found'
        when /temporada.*no válida/
          'invalid_season'
        when /unidades.*no permitidas/
          'invalid_units'
        else
          'general_validation_error'
        end
      end

      # Extraer patrones comunes de error
      def extract_common_error_patterns(sample_rows)
        error_rows = sample_rows.reject { |row| row[:success] }
        error_patterns = error_rows.map { |row| categorize_row_error(row[:error] || '') }
        
        error_patterns.group_by(&:itself).transform_values(&:count)
      end

      # Generar recomendaciones específicas
      def generate_specific_recommendations(common_errors)
        recommendations = []
        
        common_errors.each do |error_type, count|
          case error_type
          when 'missing_required_field'
            recommendations << "📝 Verificar que todas las columnas requeridas estén presentes"
          when 'invalid_price_format'
            recommendations << "💰 Revisar formato de precios (usar números decimales)"
          when 'price_definition_not_found'
            recommendations << "🔍 Verificar que categorías, sucursales y tipos de tarifa existan"
          when 'invalid_season'
            recommendations << "📅 Comprobar nombres de temporadas"
          when 'invalid_units'
            recommendations << "📊 Verificar unidades permitidas para cada definición"
          end
        end
        
        recommendations
      end

      # Formatear precio
      def format_price(price_string)
        return 'N/A' unless price_string
        
        begin
          price_value = Float(price_string)
          "€#{price_value}"
        rescue
          price_string
        end
      end

      # Serializar errores (reutilizado del otro serializer)
      def serialize_errors(errors)
        return [] unless errors

        errors.map do |error|
          {
            type: error[:type],
            message: error[:message]
          }
        end
      end

      # Formatear tamaño de archivo (reutilizado)
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
    end
  end
end
