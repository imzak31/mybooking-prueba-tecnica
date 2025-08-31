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

  describe '#find_price_definition_by_business_keys' do
    let(:mock_query_results) do
      [{
        id: 1,
        name: 'A - Barcelona - Estándar',
        type: 1,
        season_definition_id: 1,
        units_management_value_days_list: '1,2,4,15',
        units_management_value_hours_list: '1',
        units_management_value_minutes_list: '1',
        category_id: 1,
        rental_location_id: 1,
        rate_type_id: 1
      }]
    end

    before do
      allow(Infraestructure::Query).to receive(:run).and_return(mock_query_results)
    end

    it 'finds price definition for valid combination' do
      result = service.find_price_definition_by_business_keys('A', 'Barcelona', 'Estándar')
      
      expect(result).to be_present
      expect(result[:name]).to eq('A - Barcelona - Estándar')
      expect(result[:units_management_value_days_list]).to eq('1,2,4,15')
      expect(Infraestructure::Query).to have_received(:run).with(
        a_string_including('SELECT pd.id, pd.name'),
        'A', 'Barcelona', 'Estándar'
      )
    end

    it 'raises error for invalid category' do
      allow(Infraestructure::Query).to receive(:run).and_return([])
      
      expect {
        service.find_price_definition_by_business_keys('Z', 'Barcelona', 'Estándar')
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end

    it 'raises error for invalid location' do
      allow(Infraestructure::Query).to receive(:run).and_return([])
      
      expect {
        service.find_price_definition_by_business_keys('A', 'Madrid', 'Estándar')
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end

    it 'raises error for invalid rate type' do
      allow(Infraestructure::Query).to receive(:run).and_return([])
      
      expect {
        service.find_price_definition_by_business_keys('A', 'Barcelona', 'Premium')
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end
  end

  describe '#validate_season_compatibility' do
    let(:season_definition_id) { 1 }
    let(:mock_season_results) { [{ id: 1, name: 'Alta' }] }

    before do
      allow(Infraestructure::Query).to receive(:run).and_return(mock_season_results)
    end

    it 'validates season for type 1 price definition' do
      price_def_data = { type: 1, name: 'Test Definition', season_definition_id: season_definition_id }
      
      season_id = service.validate_season_compatibility(price_def_data, 'Alta')
      
      expect(season_id).to eq(1)
      expect(Infraestructure::Query).to have_received(:run).with(
        a_string_including('SELECT id, name'),
        'Alta', season_definition_id
      )
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
      price_def_data = { type: 1, name: 'Test Definition', season_definition_id: season_definition_id }
      
      expect {
        service.validate_season_compatibility(price_def_data, nil)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidSeasonError, /requiere temporada/)
    end

    it 'raises error for invalid season name' do
      allow(Infraestructure::Query).to receive(:run).and_return([])
      price_def_data = { type: 1, name: 'Test Definition', season_definition_id: season_definition_id }
      
      expect {
        service.validate_season_compatibility(price_def_data, 'Primavera')
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidSeasonError, /no válida/)
    end
  end

  describe '#validate_units_allowed' do
    let(:price_definition) do
      {
        units_management_value_days_list: '1,2,7,15',
        units_management_value_hours_list: '1,4,8,24',
        units_management_value_minutes_list: '15,30,60'
      }
    end

    context 'with valid units for days' do
      it 'returns the exact units when valid' do
        result = service.validate_units_allowed(price_definition, :days, 7)
        expect(result).to eq(7)
      end

      it 'rejects units not in the allowed list' do
        expect {
          service.validate_units_allowed(price_definition, :days, 30)
        }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError, 
                        /Unidades 30 days no permitidas/)
      end
    end

    context 'with valid units for hours' do
      it 'returns the exact units when valid' do
        result = service.validate_units_allowed(price_definition, :hours, 4)
        expect(result).to eq(4)
      end
    end

    context 'with valid units for minutes' do
      it 'returns the exact units when valid' do
        result = service.validate_units_allowed(price_definition, :minutes, 30)
        expect(result).to eq(30)
      end
    end

    context 'with months time measurement' do
      it 'allows unit 1 by default since no units_management_value_months_list exists' do
        result = service.validate_units_allowed(price_definition, :months, 1)
        expect(result).to eq(1)
      end

      it 'rejects units other than 1 for months' do
        expect {
          service.validate_units_allowed(price_definition, :months, 3)
        }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError, 
                        /Unidades 3 months no permitidas/)
      end
    end

    context 'with invalid time measurement' do
      it 'raises error for unknown time measurement' do
        expect {
          service.validate_units_allowed(price_definition, :years, 1)
        }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError, 
                        /Tipo de medición de tiempo inválido: years/)
      end
    end
  end

  describe '#upsert_price_with_validations' do
    let(:price_def_data) { { id: 1, name: 'Test Definition' } }
    let(:mock_price_repo) { double('PriceRepository') }
    let(:mock_price) { double('Price', id: 123) }

    before do
      allow(Repository::PriceRepository).to receive(:new).and_return(mock_price_repo)
    end

    it 'creates new price when none exists' do
      allow(mock_price_repo).to receive(:first).and_return(nil)
      allow(mock_price_repo).to receive(:create).and_return(mock_price)

      result = service.upsert_price_with_validations(
        price_def_data, 
        1, # season_id
        'days', 
        2, 
        25.50
      )

      expect(result[:action]).to eq(:created)
      expect(result[:price_id]).to eq(123)
      expect(mock_price_repo).to have_received(:create).with(
        price_definition_id: 1,
        season_id: 1,
        time_measurement: :days,
        units: 2,
        price: 25.50,
        included_km: 0,
        extra_km_price: 0.0
      )
    end

    it 'updates existing price' do
      existing_price = { id: 456 }
      allow(mock_price_repo).to receive(:first).and_return(double('Price', attributes: existing_price))
      allow(mock_price_repo).to receive(:update).and_return(true)

      result = service.upsert_price_with_validations(
        price_def_data, 
        1, # season_id
        'days', 
        2, 
        25.50
      )

      expect(result[:action]).to eq(:updated)
      expect(result[:price_id]).to eq(456)
      expect(mock_price_repo).to have_received(:update).with(
        456,
        price_definition_id: 1,
        season_id: 1,
        time_measurement: :days,
        units: 2,
        price: 25.50,
        included_km: 0,
        extra_km_price: 0.0
      )
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
      allow(Infraestructure::Query).to receive(:run).and_return([])
      
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
        units_management_value_minutes_list: '1'
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
      price_def_data = { id: 1 }
      mock_price_repo = double('PriceRepository')
      mock_price = double('Price', id: 123)
      
      allow(Repository::PriceRepository).to receive(:new).and_return(mock_price_repo)
      allow(mock_price_repo).to receive(:first).and_return(nil)
      allow(mock_price_repo).to receive(:create).and_return(mock_price)
      
      # Test through upsert_price_with_validations which uses the private method
      result = service.upsert_price_with_validations(
        price_def_data, 
        nil, # No season for simplicity
        'días', # Spanish variant
        1, 
        25.50
      )

      expect(result[:action]).to eq(:created)
      expect(mock_price_repo).to have_received(:create).with(
        hash_including(time_measurement: :days)
      )
    end
  end
end
