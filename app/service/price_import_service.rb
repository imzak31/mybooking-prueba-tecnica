require 'csv'

module Service
  class PriceImportService
    include Service::Concerns::PriceValidationConcern
    include Service::Concerns::CsvProcessingConcern

    # Resultado estructurado del proceso de importación
    ImportResult = Struct.new(:success?, :report, :processed_count, :error_count, :errors, keyword_init: true)

    def initialize(logger = nil)
      @logger = logger || Rails.logger
      @import_results = []
    end

    # Importar precios desde archivo CSV
    def import_from_csv(csv_file_path)
      @logger&.info("Iniciando importación de precios desde: #{csv_file_path}")
      
      begin
        # Procesar CSV con validaciones robustas
        process_csv_file(csv_file_path) do |row_info, line_number|
          import_single_price(row_info, line_number)
        end

        # Generar reporte final
        report = generate_import_report(@import_results)
        
        @logger&.info("Importación completada. Resumen: #{report[:summary]}")
        
        ImportResult.new(
          success?: report[:summary][:failed_rows] == 0,
          report: report,
          processed_count: report[:summary][:successful_rows],
          error_count: report[:summary][:failed_rows],
          errors: report[:detailed_errors]
        )
        
      rescue StandardError => e
        @logger&.error("Error crítico en importación: #{e.message}")
        @logger&.error(e.backtrace.join("\n"))
        
        ImportResult.new(
          success?: false,
          report: { error: e.message },
          processed_count: 0,
          error_count: 1,
          errors: [{ error: e.message, critical: true }]
        )
      end
    end

    # Importar precio individual con validaciones completas
    def import_single_price(row_info, line_number = nil)
      begin
        # 1. Buscar PriceDefinition a partir de claves de negocio
        price_definition_data = find_price_definition_by_business_keys(
          row_info[:category_code],
          row_info[:rental_location_name], 
          row_info[:rate_type_name]
        )

        # 2. Validar compatibilidad de temporada
        season_id = validate_season_compatibility(price_definition_data, row_info[:season_name])

        # 3. Validar y formatear datos
        units = validate_units_format(row_info[:units])
        price_value = validate_price_format(row_info[:price])
        time_measurement = row_info[:time_measurement]

        # 4. Validar que las unidades están permitidas en la PriceDefinition
        applicable_unit = validate_units_allowed(price_definition_data, time_measurement, units)

        # 5. Crear o actualizar precio con validaciones
        result = upsert_price_with_validations(
          price_definition_data,
          season_id,
          time_measurement,
          applicable_unit, # Usar la unidad aplicable, no la solicitada
          price_value
        )

        success_result = {
          success: true,
          line: line_number,
          data: row_info,
          result: result,
          price_definition: price_definition_data[:name]
        }

        @import_results << success_result
        @logger&.debug("Precio importado exitosamente: #{row_info[:category_code]} - Línea #{line_number}")
        
        success_result

      rescue PriceValidationError, CsvValidationError => e
        error_result = {
          success: false,
          line: line_number,
          data: row_info,
          error: e.message,
          error_type: e.class.name
        }

        @import_results << error_result
        @logger&.warn("Error de validación en línea #{line_number}: #{e.message}")
        
        error_result

      rescue StandardError => e
        error_result = {
          success: false,
          line: line_number,
          data: row_info,
          error: "Error inesperado: #{e.message}",
          error_type: 'UnexpectedError'
        }

        @import_results << error_result
        @logger&.error("Error inesperado en línea #{line_number}: #{e.message}")
        
        error_result
      end
    end

    # Validar archivo CSV antes de importación
    def validate_csv_file(csv_file_path)
      unless File.exist?(csv_file_path)
        raise ArgumentError, "Archivo CSV no encontrado: #{csv_file_path}"
      end

      # Verificar que es un archivo CSV válido
      begin
        CSV.foreach(csv_file_path, headers: true).first
      rescue CSV::MalformedCSVError => e
        raise ArgumentError, "Archivo CSV malformado: #{e.message}"
      end

      true
    end

    # Previsualizar importación sin guardar datos
    def preview_import(csv_file_path, max_rows: 10)
      validate_csv_file(csv_file_path)
      
      preview_results = []
      row_count = 0

      CSV.foreach(csv_file_path, headers: true).with_index(2) do |row, line_number|
        break if row_count >= max_rows

        row_data = row.to_h.transform_keys(&:strip)
        column_mapping = build_column_mapping(row_data.keys)
        
        result = process_csv_row(row_data.values, column_mapping, line_number) do |row_info|
          # Solo validar, no importar
          validate_import_feasibility(row_info)
        end

        preview_results << result
        row_count += 1
      end

      {
        sample_rows: preview_results,
        total_sample_size: row_count,
        estimated_issues: preview_results.count { |r| !r[:success] }
      }
    end

    # Generar reporte final
    def generate_import_report(import_results)
      successful_rows = import_results.count { |r| r[:success] }
      failed_rows = import_results.count { |r| !r[:success] }
      total_rows = import_results.length
      
      # Contar errores por tipo
      errors_by_type = {}
      detailed_errors = []
      
      import_results.each do |result|
        next if result[:success]
        
        error_type = result[:error_type] || 'UnknownError'
        errors_by_type[error_type] = (errors_by_type[error_type] || 0) + 1
        
        # Agregar error detallado con más contexto
        detailed_errors << {
          line: result[:line],
          error: result[:error],
          error_type: error_type,
          data: result[:data],
          suggestions: generate_error_suggestions(result[:error], result[:data])
        }
      end
      
      # Contar acciones realizadas
      created_prices = import_results.count { |r| r[:success] && r.dig(:result, :action) == :created }
      updated_prices = import_results.count { |r| r[:success] && r.dig(:result, :action) == :updated }
      
      success_rate = total_rows > 0 ? (successful_rows.to_f / total_rows * 100).round(1) : 0

      {
        summary: {
          total_rows: total_rows,
          successful_rows: successful_rows,
          failed_rows: failed_rows,
          created_prices: created_prices,
          updated_prices: updated_prices,
          success_rate: success_rate
        },
        errors_by_type: errors_by_type,
        detailed_errors: detailed_errors,
        performance: {
          processing_time: Time.current
        }
      }
    end

    private

    # Generar sugerencias de corrección para errores
    def generate_error_suggestions(error_message, data)
      suggestions = []
      
      case error_message
      when /definición de precio/i
        suggestions << "Verificar que la categoría '#{data[:category_code]}' exista"
        suggestions << "Confirmar definición de precio para #{data[:rental_location_name]} / #{data[:rate_type_name]}"
        suggestions << "Revisar si hay CategoryRentalLocationRateType configurado"
      when /temporada/i
        suggestions << "Verificar nombre de temporada: '#{data[:season_name]}'"
        suggestions << "Comprobar si la definición requiere temporadas"
        suggestions << "Revisar SeasonDefinition asociado"
      when /unidades.*permitidas/i
        suggestions << "Las unidades #{data[:units]} no están en la lista permitida"
        suggestions << "Revisar units_management_value_days_list de la PriceDefinition"
        suggestions << "Valores típicos: 1,2,4,15,30"
      when /precio/i
        suggestions << "Verificar formato numérico del precio"
        suggestions << "El precio debe ser mayor a 0"
      else
        suggestions << "Revisar formato general de los datos"
        suggestions << "Contactar soporte técnico si persiste"
      end
      
      suggestions
    end
    def process_csv_file(csv_file_path)
      validate_csv_file(csv_file_path)
      
      CSV.foreach(csv_file_path, headers: true).with_index(2) do |row, line_number|
        row_data = row.to_h.transform_keys(&:strip)
        column_mapping = build_column_mapping(row_data.keys)
        
        # Validar headers en la primera iteración
        if line_number == 2
          validate_csv_headers(row_data.keys)
        end

        process_csv_row(row_data.values, column_mapping, line_number) do |row_info|
          yield row_info, line_number if block_given?
        end
      end
    end

    # Validar factibilidad de importación sin crear datos
    def validate_import_feasibility(row_info)
      # Ejecutar todas las validaciones sin persistir
      price_definition_data = find_price_definition_by_business_keys(
        row_info[:category_code],
        row_info[:rental_location_name], 
        row_info[:rate_type_name]
      )

      season_id = validate_season_compatibility(price_definition_data, row_info[:season_name])
      
      units = validate_units_format(row_info[:units])
      validate_price_format(row_info[:price])
      
      validate_units_allowed(price_definition_data, row_info[:time_measurement], units)
      
      { feasible: true, price_definition: price_definition_data[:name] }
    end
  end
end
