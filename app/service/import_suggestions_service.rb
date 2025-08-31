module Service
  class ImportSuggestionsService
    
    def initialize
      # Cache para evitar consultas repetidas
      @cache = {
        categories: nil,
        rental_locations: nil,
        rate_types: nil,
        seasons_by_definition: nil,
        units_by_category: nil,
        time_measurements: nil
      }
    end

    # Generar sugerencias inteligentes basadas en datos reales de BD
    def generate_suggestions_for_error(error_data, error_message)
      error_type = categorize_error(error_message)
      
      case error_type
      when :price_definition_not_found
        generate_price_definition_suggestions(error_data)
      when :invalid_season
        generate_season_suggestions(error_data)
      when :invalid_units
        generate_units_suggestions(error_data)
      when :invalid_price
        generate_price_suggestions(error_data)
      else
        generate_general_suggestions(error_data)
      end
    end

    # Obtener valores válidos para selectores en UI
    def get_valid_options
      {
        categories: get_available_categories,
        rental_locations: get_available_rental_locations,
        rate_types: get_available_rate_types,
        seasons: get_available_seasons_grouped,
        units: get_available_units_grouped,
        time_measurements: get_available_time_measurements
      }
    end

    private

    def categorize_error(error_message)
      case error_message.downcase
      when /definición de precio|price.*definition/
        :price_definition_not_found
      when /temporada|season/
        :invalid_season
      when /unidades|units/
        :invalid_units
      when /precio|price/
        :invalid_price
      else
        :general_error
      end
    end

    def generate_price_definition_suggestions(error_data)
      category = error_data['category_code']
      location = error_data['rental_location_name']
      rate_type = error_data['rate_type_name']

      suggestions = []
      
      # Verificar qué parte de la combinación es problemática
      valid_categories = get_available_categories.map { |c| c[:code] }
      valid_locations = get_available_rental_locations.map { |l| l[:name] }
      valid_rate_types = get_available_rate_types.map { |r| r[:name] }

      if !valid_categories.include?(category)
        suggestions << "🔄 Cambiar categoría '<strong>#{category}</strong>' por: #{valid_categories.join(', ')}"
      end

      if !valid_locations.include?(location)
        suggestions << "🔄 Cambiar sucursal '<strong>#{location}</strong>' por: #{valid_locations.join(', ')}"
      end

      if !valid_rate_types.include?(rate_type)
        suggestions << "🔄 Cambiar tipo tarifa '<strong>#{rate_type}</strong>' por: #{valid_rate_types.join(', ')}"
      end

      # Verificar si existe alguna combinación válida para esta categoría
      if valid_categories.include?(category)
        valid_combinations = get_valid_combinations_for_category(category)
        if valid_combinations.any?
          suggestions << "✅ Combinaciones válidas para categoría #{category}:"
          valid_combinations.each do |combo|
            suggestions << "  • #{combo[:location]} / #{combo[:rate_type]}"
          end
        end
      end

      suggestions
    end

    def generate_season_suggestions(error_data)
      category = error_data['category_code']
      season = error_data['season_name']
      
      suggestions = []
      
      if category
        valid_seasons = get_available_seasons_for_category(category)
        if valid_seasons.any?
          suggestions << "🔄 Temporadas válidas para categoría <strong>#{category}</strong>: #{valid_seasons.join(', ')}"
        else
          suggestions << "ℹ️ La categoría <strong>#{category}</strong> no usa temporadas (dejar vacío)"
        end
      else
        # Mostrar todas las temporadas disponibles
        all_seasons = get_available_seasons_grouped
        suggestions << "🔄 Temporadas disponibles:"
        all_seasons.each do |def_name, seasons|
          suggestions << "  • #{def_name}: #{seasons.join(', ')}"
        end
      end

      suggestions
    end

    def generate_units_suggestions(error_data)
      category = error_data['category_code']
      units = error_data['units']
      
      suggestions = []
      
      if category
        valid_units = get_available_units_for_category(category)
        suggestions << "🔄 Unidades válidas para categoría <strong>#{category}</strong>: #{valid_units.join(', ')}"
        
        if units
          # Sugerir la unidad más cercana
          closest_unit = find_closest_valid_unit(units.to_i, valid_units)
          if closest_unit
            suggestions << "💡 Sugerencia: cambiar <strong>#{units}</strong> por <strong>#{closest_unit}</strong>"
          end
        end
      else
        # Mostrar unidades por categoría
        units_by_cat = get_available_units_grouped
        suggestions << "🔄 Unidades válidas por categoría:"
        units_by_cat.each do |cat, units_list|
          suggestions << "  • #{cat}: #{units_list.join(', ')}"
        end
      end

      suggestions
    end

    def generate_price_suggestions(error_data)
      price = error_data['price']
      
      [
        "✅ El precio debe ser un número válido mayor a 0",
        "🔄 Usar punto decimal (.) en lugar de coma (,)",
        "💡 Ejemplo: 25.50 en lugar de 25,50 o 25,50",
        price ? "🔄 Revisar valor: '<strong>#{price}</strong>'" : nil
      ].compact
    end

    def generate_general_suggestions(error_data)
      [
        "📋 Verificar que todos los campos estén completos",
        "🔍 Consultar las opciones válidas disponibles",
        "📞 Contactar soporte si el problema persiste"
      ]
    end

    # Métodos de consulta a BD con cache
    def get_available_categories
      @cache[:categories] ||= Repository::CategoryRepository.new.find_all.map do |category|
        { code: category.code, name: category.name, id: category.id }
      end
    end

    def get_available_rental_locations
      @cache[:rental_locations] ||= Repository::RentalLocationRepository.new.find_all.map do |location|
        { name: location.name, id: location.id }
      end
    end

    def get_available_rate_types
      @cache[:rate_types] ||= Repository::RateTypeRepository.new.find_all.map do |rate_type|
        { name: rate_type.name, id: rate_type.id }
      end
    end

    def get_available_seasons_grouped
      @cache[:seasons_by_definition] ||= begin
        seasons_repo = Repository::SeasonRepository.new
        season_def_repo = Repository::SeasonDefinitionRepository.new
        
        grouped = {}
        season_def_repo.find_all.each do |definition|
          all_seasons = seasons_repo.find_all
          seasons = all_seasons.select { |s| s.season_definition_id == definition.id }
          grouped[definition.name] = seasons.map(&:name)
        end
        grouped
      end
    end

    def get_available_seasons_for_category(category_code)
      # Buscar la definición de temporada para esta categoría
      category_repo = Repository::CategoryRepository.new
      categories = category_repo.find_all
      category = categories.find { |c| c.code == category_code }
      return [] unless category

      # Buscar price_definition para esta categoría usando associations
      crlrt_repo = Repository::CategoryRentalLocationRateTypeRepository.new
      associations = crlrt_repo.find_all(conditions: { category_id: category.id })
      return [] if associations.empty?

      # Obtener price_definition
      price_def_repo = Repository::PriceDefinitionRepository.new
      price_definition = price_def_repo.find_by_id(associations.first.price_definition_id)
      return [] unless price_definition

      season_definition_id = price_definition.season_definition_id
      return [] unless season_definition_id

      # Obtener temporadas para esta definición
      seasons_repo = Repository::SeasonRepository.new
      all_seasons = seasons_repo.find_all
      seasons = all_seasons.select { |s| s.season_definition_id == season_definition_id }
      seasons.map(&:name)
    end

    def get_available_units_grouped
      @cache[:units_by_category] ||= begin
        category_repo = Repository::CategoryRepository.new
        crlrt_repo = Repository::CategoryRentalLocationRateTypeRepository.new
        price_def_repo = Repository::PriceDefinitionRepository.new
        
        units_by_cat = {}
        category_repo.find_all.each do |category|
          # Buscar asociaciones para esta categoría
          associations = crlrt_repo.find_all(conditions: { category_id: category.id })
          
          if associations.any?
            # Obtener price_definitions únicos para esta categoría
            price_def_ids = associations.map(&:price_definition_id).uniq
            price_defs = price_def_ids.map { |id| price_def_repo.find_by_id(id) }.compact
            
            if price_defs.any?
              # Tomar la primera definición de precio y parsear las unidades
              units_list = price_defs.first.units_management_value_days_list
              if units_list && !units_list.empty?
                units_by_cat[category.code] = units_list.split(',').map(&:strip).map(&:to_i).sort
              end
            end
          end
        end
        units_by_cat
      end
    end

    def get_available_units_for_category(category_code)
      units_grouped = get_available_units_grouped
      units_grouped[category_code] || []
    end

    def get_available_time_measurements
      @cache[:time_measurements] ||= ['days', 'hours', 'minutes', 'months']
    end

    def get_valid_combinations_for_category(category_code)
      # Consultar combinaciones válidas desde category_rental_location_rate_types
      category_repo = Repository::CategoryRepository.new
      categories = category_repo.find_all
      category = categories.find { |c| c.code == category_code }
      return [] unless category

      crlrt_repo = Repository::CategoryRentalLocationRateTypeRepository.new
      combinations = crlrt_repo.find_all(conditions: { category_id: category.id })
      
      combinations.map do |combo|
        location = Repository::RentalLocationRepository.new.find_by_id(combo.rental_location_id)
        rate_type = Repository::RateTypeRepository.new.find_by_id(combo.rate_type_id)
        
        {
          location: location&.name,
          rate_type: rate_type&.name
        }
      end.compact
    end

    def find_closest_valid_unit(target_units, valid_units)
      return nil if valid_units.empty?
      
      # Encontrar la unidad más cercana
      valid_units.min_by { |unit| (unit - target_units).abs }
    end
  end
end
