module Service
  class ValidationSuggestionsService
    include Query::QueryConnectionConcern

    def initialize(logger = nil)
      @logger = logger || Logger.new(STDOUT)
    end

    # Obtener sugerencias basadas en datos reales de BD para errores de importación
    def get_suggestions_for_error(error_data, error_message)
      error_type = categorize_error(error_message)
      
      case error_type
      when :price_definition_not_found
        get_price_definition_suggestions(error_data)
      when :invalid_season
        get_season_suggestions(error_data)
      when :invalid_units
        get_units_suggestions(error_data)
      when :invalid_location
        get_location_suggestions(error_data)
      when :invalid_rate_type
        get_rate_type_suggestions(error_data)
      else
        get_general_suggestions(error_data)
      end
    end

    # Obtener todas las opciones válidas disponibles en el sistema
    def get_available_options
      with_connection do |connection|
        {
          categories: get_available_categories(connection),
          rental_locations: get_available_rental_locations(connection),
          rate_types: get_available_rate_types(connection),
          seasons_by_definition: get_available_seasons_grouped(connection),
          units_by_category: get_available_units_by_category(connection)
        }
      end
    end

    private

    def categorize_error(error_message)
      error_msg = error_message.downcase
      
      if error_msg.include?('definición de precio') || error_msg.include?('no se encontró')
        :price_definition_not_found
      elsif error_msg.include?('temporada')
        :invalid_season
      elsif error_msg.include?('unidades')
        :invalid_units
      elsif error_msg.include?('sucursal') || error_msg.include?('location')
        :invalid_location
      elsif error_msg.include?('tarifa') || error_msg.include?('rate')
        :invalid_rate_type
      else
        :general_error
      end
    end

    def get_price_definition_suggestions(error_data)
      category = error_data['category_code']
      location = error_data['rental_location_name']
      rate_type = error_data['rate_type_name']
      
      with_connection do |connection|
        suggestions = []
        
        # Verificar qué parte de la combinación falla
        valid_categories = get_available_categories(connection)
        valid_locations = get_available_rental_locations(connection)
        valid_rate_types = get_available_rate_types(connection)
        
        unless valid_categories.include?(category)
          suggestions << "❌ Categoría '#{category}' no existe. Válidas: #{valid_categories.join(', ')}"
        end
        
        unless valid_locations.include?(location)
          suggestions << "❌ Sucursal '#{location}' no existe. Válidas: #{valid_locations.join(', ')}"
        end
        
        unless valid_rate_types.include?(rate_type)
          suggestions << "❌ Tipo tarifa '#{rate_type}' no existe. Válidos: #{valid_rate_types.join(', ')}"
        end
        
        # Si todos los valores individuales son válidos, el problema es la combinación
        if suggestions.empty?
          available_combinations = get_available_combinations(connection)
          suggestions << "❌ Combinación #{category}/#{location}/#{rate_type} no configurada"
          suggestions << "✅ Combinaciones disponibles:"
          available_combinations.each do |combo|
            suggestions << "   • #{combo[:category]}/#{combo[:location]}/#{combo[:rate_type]}"
          end
        end
        
        suggestions
      end
    end

    def get_season_suggestions(error_data)
      category = error_data['category_code']
      season = error_data['season_name']
      
      with_connection do |connection|
        # Obtener definition_id para la categoría
        season_def_query = "
          SELECT pd.season_definition_id, sd.name as definition_name
          FROM price_definitions pd
          JOIN category_rental_location_rate_types crlrt ON pd.id = crlrt.price_definition_id
          JOIN categories c ON crlrt.category_id = c.id
          JOIN season_definitions sd ON pd.season_definition_id = sd.id
          WHERE c.code = ?
          LIMIT 1
        "
        
        result = connection.adapter.execute(season_def_query, category).first
        
        if result
          definition_id = result[:season_definition_id]
          definition_name = result[:definition_name]
          
          # Obtener temporadas válidas para esta definición
          seasons_query = "SELECT name FROM seasons WHERE season_definition_id = ?"
          valid_seasons = connection.adapter.execute(seasons_query, definition_id).map { |s| s[:name] }
          
          [
            "❌ Temporada '#{season}' no válida para categoría #{category}",
            "✅ Temporadas válidas (#{definition_name}): #{valid_seasons.join(', ')}",
            "💡 O dejar vacío si no usa temporadas"
          ]
        else
          [
            "❌ No hay configuración de temporadas para categoría #{category}",
            "💡 Dejar campo temporada vacío"
          ]
        end
      end
    end

    def get_units_suggestions(error_data)
      category = error_data['category_code']
      units = error_data['units']
      time_measurement = error_data['time_measurement'] || 'days'
      
      with_connection do |connection|
        # Obtener unidades válidas para la categoría específica
        units_query = "
          SELECT pd.units_management_value_#{time_measurement}_list as valid_units
          FROM price_definitions pd
          JOIN category_rental_location_rate_types crlrt ON pd.id = crlrt.price_definition_id
          JOIN categories c ON crlrt.category_id = c.id
          WHERE c.code = ?
          LIMIT 1
        "
        
        result = connection.adapter.execute(units_query, category).first
        
        if result && result[:valid_units]
          valid_units = result[:valid_units].split(',').map(&:strip)
          
          [
            "❌ Unidades #{units} #{time_measurement} no permitidas para categoría #{category}",
            "✅ Unidades válidas: #{valid_units.join(', ')} #{time_measurement}",
            "💡 Cambiar #{units} por uno de los valores permitidos"
          ]
        else
          [
            "❌ No hay configuración de unidades para categoría #{category}",
            "💡 Verificar que la categoría sea válida"
          ]
        end
      end
    end

    def get_location_suggestions(error_data)
      location = error_data['rental_location_name']
      
      with_connection do |connection|
        valid_locations = get_available_rental_locations(connection)
        
        [
          "❌ Sucursal '#{location}' no existe en el sistema",
          "✅ Sucursales disponibles: #{valid_locations.join(', ')}",
          "💡 Cambiar por una sucursal válida"
        ]
      end
    end

    def get_rate_type_suggestions(error_data)
      rate_type = error_data['rate_type_name']
      
      with_connection do |connection|
        valid_rate_types = get_available_rate_types(connection)
        
        [
          "❌ Tipo tarifa '#{rate_type}' no existe en el sistema",
          "✅ Tipos de tarifa disponibles: #{valid_rate_types.join(', ')}",
          "💡 Cambiar por un tipo de tarifa válido"
        ]
      end
    end

    def get_general_suggestions(error_data)
      [
        "💡 Verificar que todos los campos tengan valores válidos",
        "📋 Consultar documentación de campos requeridos",
        "🔧 Contactar soporte técnico si persiste el problema"
      ]
    end

    # Métodos auxiliares para consultar datos reales
    
    def get_available_categories(connection)
      query = "SELECT code FROM categories ORDER BY code"
      connection.adapter.execute(query).map { |row| row[:code] }
    end

    def get_available_rental_locations(connection)
      query = "SELECT name FROM rental_locations ORDER BY name"
      connection.adapter.execute(query).map { |row| row[:name] }
    end

    def get_available_rate_types(connection)
      query = "SELECT name FROM rate_types ORDER BY name"
      connection.adapter.execute(query).map { |row| row[:name] }
    end

    def get_available_seasons_grouped(connection)
      query = "
        SELECT s.name, sd.name as definition_name, sd.id as definition_id
        FROM seasons s
        JOIN season_definitions sd ON s.season_definition_id = sd.id
        ORDER BY sd.name, s.name
      "
      
      seasons = connection.adapter.execute(query)
      seasons.group_by { |s| s[:definition_name] }
             .transform_values { |group| group.map { |s| s[:name] } }
    end

    def get_available_units_by_category(connection)
      query = "
        SELECT c.code, pd.units_management_value_days_list as days_units,
               pd.units_management_value_hours_list as hours_units,
               pd.units_management_value_minutes_list as minutes_units,
               pd.units_management_value_months_list as months_units
        FROM price_definitions pd
        JOIN category_rental_location_rate_types crlrt ON pd.id = crlrt.price_definition_id
        JOIN categories c ON crlrt.category_id = c.id
        GROUP BY c.code, pd.units_management_value_days_list, 
                 pd.units_management_value_hours_list,
                 pd.units_management_value_minutes_list, 
                 pd.units_management_value_months_list
      "
      
      results = connection.adapter.execute(query)
      
      units_by_category = {}
      results.each do |row|
        category = row[:code]
        units_by_category[category] = {
          days: parse_units_list(row[:days_units]),
          hours: parse_units_list(row[:hours_units]),
          minutes: parse_units_list(row[:minutes_units]),
          months: parse_units_list(row[:months_units])
        }
      end
      
      units_by_category
    end

    def get_available_combinations(connection)
      query = "
        SELECT c.code as category, rl.name as location, rt.name as rate_type
        FROM category_rental_location_rate_types crlrt
        JOIN categories c ON crlrt.category_id = c.id
        JOIN rental_locations rl ON crlrt.rental_location_id = rl.id
        JOIN rate_types rt ON crlrt.rate_type_id = rt.id
        ORDER BY c.code, rl.name, rt.name
      "
      
      connection.adapter.execute(query).map do |row|
        {
          category: row[:category],
          location: row[:location],
          rate_type: row[:rate_type]
        }
      end
    end

    def parse_units_list(units_string)
      return [] unless units_string
      units_string.split(',').map(&:strip).reject(&:empty?)
    end
  end
end
