require 'set'

module Controller
  module PricingController
    
    def self.registered(app)
      
      app.get '/pricing' do
        @title = "Consulta de Precios"
        erb :pricing
      end

      # Endpoint temporal para debug
      app.get '/api/debug/data' do
        content_type :json
        
        begin
          season_definitions = Repository::SeasonDefinitionRepository.new.find_all
          seasons = Repository::SeasonRepository.new.find_all
          rate_types = Repository::RateTypeRepository.new.find_all
          locations = Repository::RentalLocationRepository.new.find_all
          
          { 
            success: true, 
            data: {
              season_definitions: season_definitions.map { |sd| { id: sd.id, name: sd.name } },
              seasons: seasons.map { |s| { id: s.id, name: s.name, season_definition_id: s.season_definition_id } },
              rate_types: rate_types.map { |rt| { id: rt.id, name: rt.name } },
              locations: locations.map { |loc| { id: loc.id, name: loc.name } }
            }
          }.to_json
        rescue => e
          logger.error "Error fetching debug data: #{e.message}"
          status 500
          { 
            success: false, 
            error: e.message 
          }.to_json
        end
      end

      # API endpoints para los filtros en cascada
      app.get '/api/pricing/rental-locations' do
        content_type :json
        
        begin
          locations = Repository::RentalLocationRepository.new.find_all
          locations_data = locations.map { |loc| { id: loc.id, name: loc.name } }
          
          { 
            success: true, 
            data: locations_data 
          }.to_json
        rescue => e
          logger.error "Error fetching rental locations: #{e.message}"
          status 500
          { 
            success: false, 
            error: "Error interno del servidor" 
          }.to_json
        end
      end

      app.get '/api/pricing/categories' do
        content_type :json
        
        begin
          location_id = params[:rental_location_id]
          
          if location_id
            # Filtrar categorías por ubicación
            categories = Repository::CategoryRepository.new.find_all.select do |cat|
              # Verificar si la categoría tiene definiciones de precio para esta ubicación
              Repository::CategoryRentalLocationRateTypeRepository.new.any?(
                category_id: cat.id,
                rental_location_id: location_id.to_i
              )
            end
          else
            categories = Repository::CategoryRepository.new.find_all
          end
          
          categories_data = categories.map do |cat|
            { id: cat.id, code: cat.code, name: cat.name }
          end
          
          { 
            success: true, 
            data: categories_data 
          }.to_json
        rescue => e
          logger.error "Error fetching categories: #{e.message}"
          status 500
          { 
            success: false, 
            error: "Error interno del servidor" 
          }.to_json
        end
      end

      app.get '/api/pricing/rate-types' do
        content_type :json
        
        begin
          location_id = params[:rental_location_id]
          
          if location_id
            # Filtrar rate types por ubicación - obtener solo los que tienen definiciones de precio
            rate_types = Repository::RateTypeRepository.new.find_all.select do |rt|
              Repository::CategoryRentalLocationRateTypeRepository.new.any?(
                rental_location_id: location_id.to_i,
                rate_type_id: rt.id
              )
            end
          else
            rate_types = Repository::RateTypeRepository.new.find_all
          end
          
          rate_types_data = rate_types.map { |rt| { id: rt.id, name: rt.name } }
          
          { 
            success: true, 
            data: rate_types_data 
          }.to_json
        rescue => e
          logger.error "Error fetching rate types: #{e.message}"
          status 500
          { 
            success: false, 
            error: "Error interno del servidor" 
          }.to_json
        end
      end

      app.get '/api/pricing/season-definitions' do
        content_type :json
        
        begin
          location_id = params[:rental_location_id]
          rate_type_id = params[:rate_type_id]
          
          unless location_id && rate_type_id
            status 400
            return { 
              success: false, 
              error: "Parámetros requeridos: rental_location_id, rate_type_id" 
            }.to_json
          end
          
          # Obtener price definitions para la ubicación y tipo de tarifa
          price_definition_links = Repository::CategoryRentalLocationRateTypeRepository.new.find_all(
            rental_location_id: location_id.to_i,
            rate_type_id: rate_type_id.to_i
          )
          
          season_definitions_set = Set.new
          has_no_season = false
          
          price_definition_links.each do |link|
            price_definition = Repository::PriceDefinitionRepository.new.first(id: link.price_definition_id)
            
            if price_definition.season_definition_id
              season_definitions_set.add(price_definition.season_definition_id)
            else
              has_no_season = true
            end
          end
          
          # Convertir a array de hashes con nombres
          season_definitions_data = []
          
          season_definitions_set.each do |sd_id|
            season_definition = Repository::SeasonDefinitionRepository.new.first(id: sd_id)
            season_definitions_data << {
              id: season_definition.id,
              name: season_definition.name
            }
          end
          
          # Agregar "Sin temporadas" si aplica
          if has_no_season
            season_definitions_data.unshift({ id: nil, name: "Sin temporadas" })
          end
          
          { 
            success: true, 
            data: season_definitions_data 
          }.to_json
        rescue => e
          logger.error "Error fetching season definitions: #{e.message}"
          status 500
          { 
            success: false, 
            error: "Error interno del servidor" 
          }.to_json
        end
      end

      app.get '/api/pricing/seasons' do
        content_type :json
        
        begin
          season_definition_id = params[:season_definition_id]
          
          unless season_definition_id
            status 400
            return { 
              success: false, 
              error: "Parámetro requerido: season_definition_id" 
            }.to_json
          end
          
          if season_definition_id == "null" || season_definition_id.empty?
            # Sin temporadas
            return { 
              success: true, 
              data: [{ id: nil, name: "Sin temporada" }] 
            }.to_json
          end
          
          seasons = Repository::SeasonRepository.new.find_all(
            season_definition_id: season_definition_id.to_i
          )
          
          seasons_data = seasons.map { |season| { id: season.id, name: season.name } }
          
          { 
            success: true, 
            data: seasons_data 
          }.to_json
        rescue => e
          logger.error "Error fetching seasons: #{e.message}"
          status 500
          { 
            success: false, 
            error: "Error interno del servidor" 
          }.to_json
        end
      end

      app.get '/api/pricing/prices' do
        content_type :json
        
        begin
          location_id = params[:rental_location_id]
          rate_type_id = params[:rate_type_id]
          season_definition_id = params[:season_definition_id]
          season_id = params[:season_id]
          time_measurement = params[:time_measurement]&.to_i || 2  # Default a días (2)
          
          unless location_id && rate_type_id
            status 400
            return { 
              success: false, 
              error: "Parámetros requeridos: rental_location_id, rate_type_id" 
            }.to_json
          end
          
          # Obtener todas las relaciones categoría-ubicación-tarifa para estos filtros
          price_definition_links = Repository::CategoryRentalLocationRateTypeRepository.new.find_all(
            rental_location_id: location_id.to_i,
            rate_type_id: rate_type_id.to_i
          )
          
          prices_by_category = {}
          
          price_definition_links.each do |link|
            price_definition = Repository::PriceDefinitionRepository.new.first(id: link.price_definition_id)
            category = Repository::CategoryRepository.new.first(id: link.category_id)
            
            # Filtrar por definición de temporada si se especifica
            if season_definition_id && season_definition_id != "null" && !season_definition_id.empty?
              next if price_definition.season_definition_id.to_s != season_definition_id
            elsif season_definition_id == "null"
              next unless price_definition.season_definition_id.nil?
            end
            
            # Obtener precios para esta definición
            all_prices = Repository::PriceRepository.new.find_all(
              price_definition_id: price_definition.id
            )
            
            # Filtrar por unidad de tiempo
            # Mapear códigos numéricos a symbols según la BD
            time_measurement_map = { 1 => :months, 2 => :days, 3 => :hours, 4 => :minutes }
            time_measurement_symbol = time_measurement_map[time_measurement] || :days
            
            filtered_prices = all_prices.select { |p| p.time_measurement == time_measurement_symbol }
            
            # Si se especifica temporada específica, filtrar por ella
            if season_id && season_id != "null" && !season_id.empty?
              filtered_prices = filtered_prices.select { |p| p.season_id.to_s == season_id }
            end
            
            next if filtered_prices.empty?
            
            category_key = category.code
            
            unless prices_by_category[category_key]
              prices_by_category[category_key] = {
                category_code: category.code,
                category_name: category.name,
                prices: []
              }
            end
            
            filtered_prices.each do |price|
              season_name = "Sin temporada"
              if price.season_id
                season = Repository::SeasonRepository.new.first(id: price.season_id)
                season_name = season.name if season
              end
              
              prices_by_category[category_key][:prices] << {
                id: price.id,
                units: price.units,
                price: price.price.to_f,
                price_formatted: "€#{price.price.to_f.round(2)}",
                time_measurement: price.time_measurement.to_s,
                season_name: season_name,
                price_definition_name: price_definition.name,
                excess: price_definition.excess ? price_definition.excess.to_f : 0,
                deposit: price_definition.deposit ? price_definition.deposit.to_f : 0,
                excess_formatted: price_definition.excess ? "€#{price_definition.excess.to_f.round(2)}" : "€0",
                deposit_formatted: price_definition.deposit ? "€#{price_definition.deposit.to_f.round(2)}" : "€0"
              }
            end
          end
          
          # Ordenar precios por unidades dentro de cada categoría
          prices_by_category.each do |_, category_data|
            category_data[:prices].sort_by! { |p| p[:units] }
          end
          
          { 
            success: true, 
            data: prices_by_category.values,
            filters: {
              rental_location_id: location_id,
              rate_type_id: rate_type_id,
              season_definition_id: season_definition_id,
              season_id: season_id,
              time_measurement: time_measurement
            }
          }.to_json
        rescue => e
          logger.error "Error fetching prices: #{e.message}"
          status 500
          { 
            success: false, 
            error: "Error interno del servidor" 
          }.to_json
        end
      end

    end
  end
end
