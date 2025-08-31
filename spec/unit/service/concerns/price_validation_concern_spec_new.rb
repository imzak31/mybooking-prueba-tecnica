require 'spec_helper'

# Test service class que incluye el concern
class TestPriceValidationService
  include Service::Concerns::PriceValidationConcern
  
  def initialize
    @logger = Logger.new(StringIO.new)
  end
end

RSpec.describe Service::Concerns::PriceValidationConcern, unit: true do
  let(:service) { TestPriceValidationService.new }
  
  # Create test data
  let!(:category_a) { create(:category, code: 'A', name: 'Scooter 125cc') }
  let!(:rental_location_bcn) { create(:rental_location, name: 'Barcelona') }
  let!(:rate_type_std) { create(:rate_type, name: 'Estándar') }
  let!(:season_definition) { create(:season_definition, name: 'Temporadas scooters') }
  let!(:season_alta) { create(:season, name: 'Alta', season_definition: season_definition) }
  
  let!(:price_definition) do
    create(:price_definition,
           name: 'A - Barcelona - Estándar',
           rate_type: rate_type_std,
           season_definition: season_definition,
           units_management_value_days_list: '1,2,4,15')
  end
  
  let!(:crlrt) do
    create(:category_rental_location_rate_type,
           category: category_a,
           rental_location: rental_location_bcn,
           rate_type: rate_type_std,
           price_definition: price_definition)
  end

  describe '#find_price_definition_by_business_keys' do
    it 'finds price definition for valid combination' do
      result = service.find_price_definition_by_business_keys('A', 'Barcelona', 'Estándar')
      
      expect(result).to be_present
      expect(result[:name]).to eq('A - Barcelona - Estándar')
      expect(result[:units_management_value_days_list]).to eq('1,2,4,15')
    end

    it 'raises error for invalid category' do
      expect {
        service.find_price_definition_by_business_keys('Z', 'Barcelona', 'Estándar')
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end

    it 'raises error for invalid location' do
      expect {
        service.find_price_definition_by_business_keys('A', 'Madrid', 'Estándar')
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end

    it 'raises error for invalid rate type' do
      expect {
        service.find_price_definition_by_business_keys('A', 'Barcelona', 'Premium')
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end
  end

  describe '#validate_season_compatibility' do
    it 'validates season for type 1 price definition' do
      price_def_data = { type: 1, name: 'Test Definition', season_definition_id: season_definition.id }
      
      season_id = service.validate_season_compatibility(price_def_data, 'Alta')
      
      expect(season_id).to eq(season_alta.id)
    end

    it 'returns nil for type 2 price definition with no season' do
      price_def_data = { type: 2, name: 'Test Definition', season_definition_id: nil }
      
      season_id = service.validate_season_compatibility(price_def_data, nil)
      
      expect(season_id).to be_nil
    end

    it 'raises error for type 2 price definition with season' do
      price_def_data = { type: 2, name: 'Test Definition', season_definition_id: nil }
      
      expect {
        service.validate_season_compatibility(price_def_data, 'Alta')
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidSeasonError, /no admite temporadas/)
    end

    it 'raises error for type 1 price definition without season' do
      price_def_data = { type: 1, name: 'Test Definition', season_definition_id: season_definition.id }
      
      expect {
        service.validate_season_compatibility(price_def_data, nil)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidSeasonError, /requiere temporada/)
    end

    it 'raises error for invalid season name' do
      price_def_data = { type: 1, name: 'Test Definition', season_definition_id: season_definition.id }
      
      expect {
        service.validate_season_compatibility(price_def_data, 'Primavera')
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidSeasonError, /no válida/)
    end
  end

  describe '#validate_units_allowed' do
    let(:price_def_data) do
      {
        id: price_definition.id,
        units_management_value_days_list: '1,2,4,15',
        units_management_value_hours_list: '1',
        units_management_value_minutes_list: '1',
        units_management_value_months_list: '1'
      }
    end

    it 'validates allowed units for days' do
      result = service.validate_units_allowed(price_def_data, 'days', 2)
      expect(result).to eq(2)
    end

    it 'raises error for invalid units' do
      expect {
        service.validate_units_allowed(price_def_data, 'days', 10)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError, /no permitidas/)
    end

    it 'handles different time measurements' do
      result = service.validate_units_allowed(price_def_data, 'hours', 1)
      expect(result).to eq(1)
    end

    it 'raises error for invalid time measurement' do
      expect {
        service.validate_units_allowed(price_def_data, 'invalid_time', 1)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError, /inválido/)
    end
  end

  describe '#upsert_price_with_validations' do
    let(:price_def_data) { { id: price_definition.id, name: 'Test Definition' } }

    it 'creates new price when none exists' do
      result = service.upsert_price_with_validations(
        price_def_data, 
        season_alta.id, 
        'days', 
        2, 
        25.50
      )

      expect(result[:action]).to eq(:created)
      expect(result[:price_id]).to be_present
    end

    it 'updates existing price' do
      # Create an existing price first
      existing_price = create(:price, 
                             price_definition: price_definition,
                             season: season_alta,
                             time_measurement: :days,
                             units: 2,
                             price: 20.00)

      result = service.upsert_price_with_validations(
        price_def_data, 
        season_alta.id, 
        'days', 
        2, 
        25.50
      )

      expect(result[:action]).to eq(:updated)
      expect(result[:price_id]).to eq(existing_price.id)
    end
  end

  describe 'error classes' do
    it 'defines custom error classes properly' do
      expect(Service::Concerns::PriceValidationConcern::PriceValidationError).to be < StandardError
      expect(Service::Concerns::PriceValidationConcern::InvalidUnitsError).to be < Service::Concerns::PriceValidationConcern::PriceValidationError
      expect(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError).to be < Service::Concerns::PriceValidationConcern::PriceValidationError
      expect(Service::Concerns::PriceValidationConcern::InvalidSeasonError).to be < Service::Concerns::PriceValidationConcern::PriceValidationError
    end

    it 'provides meaningful error messages' do
      error = nil
      begin
        service.find_price_definition_by_business_keys('Z', 'Barcelona', 'Estándar')
      rescue Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError => e
        error = e
      end

      expect(error).to be_present
      expect(error.message).to include('No se encontró definición de precio')
      expect(error.message).to include('Z / Barcelona / Estándar')
    end
  end

  describe 'private method behavior' do
    it 'correctly parses units lists' do
      # Test the private parse_units_list method indirectly through validate_units_allowed
      price_def_data = {
        id: 1,
        units_management_value_days_list: '1,2,4,15',
        units_management_value_hours_list: '1',
        units_management_value_minutes_list: '1',
        units_management_value_months_list: '1'
      }

      # Should work for valid units
      expect {
        service.validate_units_allowed(price_def_data, 'days', 4)
      }.not_to raise_error

      # Should fail for invalid units
      expect {
        service.validate_units_allowed(price_def_data, 'days', 3)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError)
    end

    it 'correctly maps time measurements' do
      price_def_data = { id: price_definition.id }
      
      # Test through upsert_price_with_validations which uses the private method
      result = service.upsert_price_with_validations(
        price_def_data, 
        nil, # No season for simplicity
        'días', # Spanish variant
        1, 
        25.50
      )

      expect(result[:action]).to be_in([:created, :updated])
    end
  end
end
