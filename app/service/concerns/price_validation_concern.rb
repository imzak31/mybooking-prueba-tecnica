module Service
  module Concerns
    module PriceValidationConcern
      extend ActiveSupport::Concern

      # Errores específicos del dominio de pricing
      class PriceValidationError < StandardError; end
      class InvalidUnitsError < PriceValidationError; end
      class PriceDefinitionNotFoundError < PriceValidationError; end
      class InvalidSeasonError < PriceValidationError; end

      included do
        # Métodos de clase disponibles cuando se incluye el concern
      end

      # Validar que las unidades están permitidas en la PriceDefinition
      def validate_units_allowed(price_definition, time_measurement, units)
        case time_measurement.to_sym
        when :days
          allowed_units = parse_units_list(price_definition[:units_management_value_days_list])
        when :hours
          allowed_units = parse_units_list(price_definition[:units_management_value_hours_list])
        when :minutes
          allowed_units = parse_units_list(price_definition[:units_management_value_minutes_list])
        when :months
          # Months are supported via time_measurement_months boolean, but units are fixed at 1
          # Since there's no units_management_value_months_list, default to [1]
          allowed_units = [1]
        else
          raise InvalidUnitsError, "Tipo de medición de tiempo inválido: #{time_measurement}"
        end

        # Encontrar el rango correcto para las unidades solicitadas
        applicable_unit = find_applicable_unit(units, allowed_units)
        
        unless applicable_unit
          raise InvalidUnitsError, 
            "Unidades #{units} #{time_measurement} no permitidas. Unidades válidas: #{allowed_units.join(', ')}"
        end

        applicable_unit
      end

      # Buscar PriceDefinition a partir de categoría, sucursal y tipo de tarifa
      def find_price_definition_by_business_keys(category_code, rental_location_name, rate_type_name)
        sql = <<-SQL
          SELECT pd.id, pd.name, pd.type, pd.season_definition_id,
                 pd.units_management_value_days_list,
                 pd.units_management_value_hours_list,
                 pd.units_management_value_minutes_list,
                 c.id as category_id, rl.id as rental_location_id, rt.id as rate_type_id
          FROM price_definitions pd
          JOIN category_rental_location_rate_types crlrt ON pd.id = crlrt.price_definition_id
          JOIN categories c ON crlrt.category_id = c.id
          JOIN rental_locations rl ON crlrt.rental_location_id = rl.id
          JOIN rate_types rt ON crlrt.rate_type_id = rt.id
          WHERE c.code = ? AND rl.name = ? AND rt.name = ?
        SQL

        results = Infraestructure::Query.run(sql, category_code, rental_location_name, rate_type_name)
        
        if results.empty?
          raise PriceDefinitionNotFoundError, 
            "No se encontró definición de precio para: #{category_code} / #{rental_location_name} / #{rate_type_name}"
        end

        results.first
      end

      # Validar compatibilidad de temporada con PriceDefinition
      def validate_season_compatibility(price_definition_data, season_name)
        # Si la PriceDefinition es tipo 2 (sin temporadas), no debe tener temporada
        if price_definition_data[:type] == 2 && season_name.present?
          raise InvalidSeasonError, 
            "La definición de precio '#{price_definition_data[:name]}' no admite temporadas"
        end

        # Si la PriceDefinition es tipo 1 (con temporadas), debe tener temporada válida
        if price_definition_data[:type] == 1
          if season_name.blank?
            raise InvalidSeasonError, 
              "La definición de precio '#{price_definition_data[:name]}' requiere temporada"
          end

          # Validar que la temporada pertenece al season_definition correcto
          season = find_season_by_name_and_definition(season_name, price_definition_data[:season_definition_id])
          unless season
            raise InvalidSeasonError, 
              "Temporada '#{season_name}' no válida para la definición de precios '#{price_definition_data[:name]}'"
          end

          return season[:id]
        end

        nil # Sin temporada para tipo 2
      end

      # Crear o actualizar precio con validaciones
      def upsert_price_with_validations(price_definition_data, season_id, time_measurement, units, price_value)
        # Buscar precio existente
        existing_price = find_existing_price(
          price_definition_data[:id], 
          season_id, 
          time_measurement, 
          units
        )

        price_data = {
          price_definition_id: price_definition_data[:id],
          season_id: season_id,
          time_measurement: map_time_measurement_to_enum(time_measurement),
          units: units,
          price: price_value.to_f,
          included_km: 0,
          extra_km_price: 0.0
        }

        if existing_price
          # Actualizar precio existente
          Repository::PriceRepository.new.update(existing_price[:id], price_data)
          { action: :updated, price_id: existing_price[:id] }
        else
          # Crear nuevo precio
          price_repo = Repository::PriceRepository.new
          new_price = price_repo.create(price_data)
          { action: :created, price_id: new_price.id }
        end
      end

      private

      # Parsear lista de unidades permitidas
      def parse_units_list(units_string)
        return [1] if units_string.blank?
        
        units_string.split(',').map(&:strip).map(&:to_i).sort
      end

      # Encontrar la unidad aplicable para un valor dado
      def find_applicable_unit(requested_units, allowed_units)
        # Solo permitir unidades exactas - NO rangos
        # La especificación dice: "el sistema no deberá cargar las tarifas de 30 días"
        # si solo están definidas 1,2,4,15
        
        unless allowed_units.include?(requested_units)
          return nil # Unidad no permitida
        end
        
        requested_units
      end

      # Buscar temporada por nombre y definición
      def find_season_by_name_and_definition(season_name, season_definition_id)
        sql = <<-SQL
          SELECT id, name 
          FROM seasons 
          WHERE name = ? AND season_definition_id = ?
        SQL

        results = Infraestructure::Query.run(sql, season_name, season_definition_id)
        results.first
      end

      # Buscar precio existente
      def find_existing_price(price_definition_id, season_id, time_measurement, units)
        conditions = {
          price_definition_id: price_definition_id,
          time_measurement: map_time_measurement_to_enum(time_measurement),
          units: units
        }
        
        # Agregar season_id solo si no es nil
        conditions[:season_id] = season_id if season_id

        Repository::PriceRepository.new.first(conditions: conditions)&.attributes
      end

      # Mapear string a enum de DataMapper
      def map_time_measurement_to_enum(time_measurement_string)
        case time_measurement_string.to_s.downcase
        when 'days', 'día', 'días'
          :days
        when 'hours', 'hora', 'horas'
          :hours
        when 'minutes', 'minuto', 'minutos'
          :minutes
        when 'months', 'mes', 'meses'
          :months
        else
          :days  # default a días
        end
      end
    end
  end
end
