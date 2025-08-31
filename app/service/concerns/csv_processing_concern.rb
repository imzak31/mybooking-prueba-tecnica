module Service
  module Concerns
    module CsvProcessingConcern
      extend ActiveSupport::Concern

      # Errores específicos de procesamiento CSV
      class CsvValidationError < StandardError; end
      class InvalidHeaderError < CsvValidationError; end
      class InvalidRowDataError < CsvValidationError; end

      # Configuración de columnas esperadas en el CSV
      REQUIRED_COLUMNS = %w[
        category_code
        rental_location_name  
        rate_type_name
        season_name
        time_measurement
        units
        price
      ].freeze

      OPTIONAL_COLUMNS = %w[
        included_km
        extra_km_price
      ].freeze

      included do
        attr_reader :import_results
      end

      # Validar headers del CSV
      def validate_csv_headers(headers)
        normalized_headers = headers.map(&:strip).map(&:downcase)
        
        missing_columns = REQUIRED_COLUMNS - normalized_headers
        
        if missing_columns.any?
          raise InvalidHeaderError, 
            "Columnas requeridas faltantes: #{missing_columns.join(', ')}"
        end

        # Retornar mapeo de índices para acceso rápido
        build_column_mapping(headers)
      end

      # Procesar fila individual del CSV con validaciones robustas
      def process_csv_row(row_data, column_mapping, line_number)
        row_info = nil
        
        begin
          # Extraer datos de la fila
          row_info = extract_row_data(row_data, column_mapping)
          
          # Validar datos básicos
          validate_row_data(row_info, line_number)
          
          # Log del procesamiento
          log_row_processing(row_info, line_number)
          
          yield row_info if block_given?
          
          { success: true, data: row_info, line: line_number }
          
        rescue StandardError => e
          # Usar datos procesados si están disponibles, sino usar datos raw
          error_data = row_info || extract_row_data_safe(row_data, column_mapping)
          
          error_result = {
            success: false,
            error: e.message,
            line: line_number,
            data: error_data
          }
          
          log_row_error(error_result)
          error_result
        end
      end

      # Extraer datos de fila de forma segura (no lanza excepciones)
      def extract_row_data_safe(row_data, column_mapping)
        begin
          extract_row_data(row_data, column_mapping)
        rescue
          # Si falla la extracción, crear hash básico con datos disponibles
          mapped_data = {}
          column_mapping.each do |column_name, index|
            mapped_data[column_name] = row_data[index] if index && row_data[index]
          end
          mapped_data
        end
      end

      # Generar reporte detallado de importación
      def generate_import_report(results)
        total_rows = results.length
        successful_rows = results.count { |r| r[:success] }
        failed_rows = total_rows - successful_rows
        
        created_count = results.count { |r| r[:success] && r.dig(:result, :action) == :created }
        updated_count = results.count { |r| r[:success] && r.dig(:result, :action) == :updated }
        
        errors_by_type = results
          .reject { |r| r[:success] }
          .group_by { |r| extract_error_type(r[:error]) }
          .transform_values(&:count)

        {
          summary: {
            total_rows: total_rows,
            successful_rows: successful_rows,
            failed_rows: failed_rows,
            created_prices: created_count,
            updated_prices: updated_count,
            success_rate: (successful_rows.to_f / total_rows * 100).round(2)
          },
          errors_by_type: errors_by_type,
          detailed_errors: results.reject { |r| r[:success] }.first(10), # Primeros 10 errores
          timestamp: Time.now.utc
        }
      end

      # Validar formato de precio
      def validate_price_format(price_string)
        return nil if price_string.blank?
        
        # Limpiar formato (quitar espacios, comas como separadores de miles)
        cleaned_price = price_string.to_s.gsub(/[^\d.,]/, '')
        
        # Convertir comas a puntos para decimales
        cleaned_price = cleaned_price.tr(',', '.')
        
        begin
          price_value = Float(cleaned_price)
          
          if price_value < 0
            raise InvalidRowDataError, "El precio no puede ser negativo: #{price_string}"
          end
          
          price_value
        rescue ArgumentError
          raise InvalidRowDataError, "Formato de precio inválido: #{price_string}"
        end
      end

      # Validar unidades
      def validate_units_format(units_string)
        return nil if units_string.blank?
        
        begin
          units_value = Integer(units_string)
          
          if units_value <= 0
            raise InvalidRowDataError, "Las unidades deben ser positivas: #{units_string}"
          end
          
          units_value
        rescue ArgumentError
          raise InvalidRowDataError, "Formato de unidades inválido: #{units_string}"
        end
      end

      private

      # Construir mapeo de columnas para acceso eficiente
      def build_column_mapping(headers)
        mapping = {}
        headers.each_with_index do |header, index|
          normalized_header = header.strip.downcase
          mapping[normalized_header] = index
        end
        mapping
      end

      # Extraer datos de la fila usando el mapeo de columnas
      def extract_row_data(row_data, column_mapping)
        {
          category_code: get_column_value(row_data, column_mapping, 'category_code')&.strip,
          rental_location_name: get_column_value(row_data, column_mapping, 'rental_location_name')&.strip,
          rate_type_name: get_column_value(row_data, column_mapping, 'rate_type_name')&.strip,
          season_name: get_column_value(row_data, column_mapping, 'season_name')&.strip,
          time_measurement: get_column_value(row_data, column_mapping, 'time_measurement')&.strip,
          units: get_column_value(row_data, column_mapping, 'units')&.strip,
          price: get_column_value(row_data, column_mapping, 'price')&.strip,
          included_km: get_column_value(row_data, column_mapping, 'included_km')&.strip,
          extra_km_price: get_column_value(row_data, column_mapping, 'extra_km_price')&.strip
        }
      end

      # Obtener valor de columna de forma segura
      def get_column_value(row_data, column_mapping, column_name)
        index = column_mapping[column_name]
        return nil unless index
        
        row_data[index]
      end

      # Validar datos de la fila
      def validate_row_data(row_info, line_number)
        # Validar campos requeridos
        required_fields = [:category_code, :rental_location_name, :rate_type_name, :time_measurement, :units, :price]
        
        required_fields.each do |field|
          if row_info[field].blank?
            raise InvalidRowDataError, "Campo requerido vacío: #{field}"
          end
        end

        # Validar formatos específicos
        validate_price_format(row_info[:price])
        validate_units_format(row_info[:units])
        
        # Validar time_measurement
        valid_measurements = %w[days hours minutes months día días hora horas minuto minutos mes meses]
        unless valid_measurements.include?(row_info[:time_measurement].downcase)
          raise InvalidRowDataError, 
            "Medición de tiempo inválida: #{row_info[:time_measurement]}. Valores válidos: #{valid_measurements.join(', ')}"
        end
      end

      # Extraer tipo de error para agrupación en reporte
      def extract_error_type(error_message)
        case error_message
        when /Campo requerido vacío/
          'Campos requeridos faltantes'
        when /Formato de precio inválido/
          'Formato de precio inválido'
        when /Unidades .* no permitidas/
          'Unidades no permitidas'
        when /No se encontró definición de precio/
          'Definición de precio no encontrada'
        when /Temporada .* no válida/
          'Temporada inválida'
        when /Medición de tiempo inválida/
          'Medición de tiempo inválida'
        else
          'Error general'
        end
      end

      # Logging estructurado del procesamiento
      def log_row_processing(row_info, line_number)
        logger&.debug("Procesando línea #{line_number}: #{row_info[:category_code]} / #{row_info[:rental_location_name]} / #{row_info[:rate_type_name]}")
      end

      # Logging de errores
      def log_row_error(error_result)
        logger&.warn("Error en línea #{error_result[:line]}: #{error_result[:error]}")
      end

      # Obtener logger del contexto actual
      def logger
        @logger || Logger.new(STDOUT)
      end
    end
  end
end
