require 'spec_helper'

# Test class to include the concern
class TestPriceValidationService
  include Service::Concerns::PriceValidationConcern
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

  describe '#find_applicable_price_definition' do
    it 'finds price definition for valid combination' do
      result = service.find_applicable_price_definition('A', 'Barcelona', 'Estándar')
      
      expect(result).to eq(price_definition)
    end

    it 'returns nil for invalid category' do
      result = service.find_applicable_price_definition('Z', 'Barcelona', 'Estándar')
      
      expect(result).to be_nil
    end

    it 'returns nil for invalid location' do
      result = service.find_applicable_price_definition('A', 'Madrid', 'Estándar')
      
      expect(result).to be_nil
    end

    it 'returns nil for invalid rate type' do
      result = service.find_applicable_price_definition('A', 'Barcelona', 'Premium')
      
      expect(result).to be_nil
    end

    it 'handles case-insensitive matching' do
      result = service.find_applicable_price_definition('a', 'barcelona', 'estándar')
      
      expect(result).to eq(price_definition)
    end
  end

  describe '#find_applicable_season' do
    it 'finds season for valid combination' do
      result = service.find_applicable_season(price_definition, 'Alta')
      
      expect(result).to eq(season_alta)
    end

    it 'returns nil for invalid season name' do
      result = service.find_applicable_season(price_definition, 'Primavera')
      
      expect(result).to be_nil
    end

    it 'returns nil when price definition has no season definition' do
      price_def_no_season = create(:price_definition, 
                                  name: 'No Season PD',
                                  rate_type: rate_type_std,
                                  season_definition: nil)
      
      result = service.find_applicable_season(price_def_no_season, 'Alta')
      
      expect(result).to be_nil
    end

    it 'handles case-insensitive matching' do
      result = service.find_applicable_season(price_definition, 'alta')
      
      expect(result).to eq(season_alta)
    end
  end

  describe '#find_applicable_unit' do
    it 'finds valid unit for category' do
      result = service.find_applicable_unit(price_definition, 'days', 2)
      
      expect(result).to eq(2)
    end

    it 'returns nil for invalid unit' do
      result = service.find_applicable_unit(price_definition, 'days', 10)
      
      expect(result).to be_nil
    end

    it 'handles different time measurements' do
      # For now, only days is implemented, but test the interface
      result = service.find_applicable_unit(price_definition, 'hours', 1)
      
      # Should return nil as hours logic is not implemented
      expect(result).to be_nil
    end

    it 'validates units from price definition' do
      # Test with empty units list
      empty_pd = create(:price_definition,
                       name: 'Empty Units PD',
                       rate_type: rate_type_std,
                       units_management_value_days_list: '')
      
      result = service.find_applicable_unit(empty_pd, 'days', 1)
      
      expect(result).to be_nil
    end
  end

  describe '#validate_price_data' do
    let(:valid_data) do
      {
        'category_code' => 'A',
        'rental_location_name' => 'Barcelona',
        'rate_type_name' => 'Estándar',
        'season_name' => 'Alta',
        'time_measurement' => 'days',
        'units' => 2,
        'price' => 25.50
      }
    end

    it 'validates correct data successfully' do
      result = service.validate_price_data(valid_data)
      
      expect(result[:valid]).to be true
      expect(result[:price_definition]).to eq(price_definition)
      expect(result[:season]).to eq(season_alta)
      expect(result[:units]).to eq(2)
    end

    it 'fails validation for invalid price definition' do
      invalid_data = valid_data.merge('category_code' => 'Z')
      
      expect {
        service.validate_price_data(invalid_data)
      }.to raise_error(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError)
    end

    it 'fails validation for invalid season' do
      invalid_data = valid_data.merge('season_name' => 'Primavera')
      
      expect {
        service.validate_price_data(invalid_data)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidSeasonError)
    end

    it 'fails validation for invalid units' do
      invalid_data = valid_data.merge('units' => 10)
      
      expect {
        service.validate_price_data(invalid_data)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidUnitsError)
    end

    it 'fails validation for invalid price' do
      invalid_data = valid_data.merge('price' => -5)
      
      expect {
        service.validate_price_data(invalid_data)
      }.to raise_error(Service::Concerns::PriceValidationConcern::InvalidPriceError)
    end

    it 'handles missing season_name (empty season)' do
      data_no_season = valid_data.merge('season_name' => '')
      
      result = service.validate_price_data(data_no_season)
      
      expect(result[:valid]).to be true
      expect(result[:season]).to be_nil
    end

    it 'handles nil season_name' do
      data_nil_season = valid_data.merge('season_name' => nil)
      
      result = service.validate_price_data(data_nil_season)
      
      expect(result[:valid]).to be true
      expect(result[:season]).to be_nil
    end
  end

  describe 'custom error classes' do
    it 'defines custom error classes' do
      expect(Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError).to be < StandardError
      expect(Service::Concerns::PriceValidationConcern::InvalidSeasonError).to be < StandardError
      expect(Service::Concerns::PriceValidationConcern::InvalidUnitsError).to be < StandardError
      expect(Service::Concerns::PriceValidationConcern::InvalidPriceError).to be < StandardError
    end

    it 'provides meaningful error messages' do
      begin
        service.validate_price_data({ 'category_code' => 'Z', 'rental_location_name' => 'Barcelona', 'rate_type_name' => 'Estándar' })
      rescue Service::Concerns::PriceValidationConcern::PriceDefinitionNotFoundError => e
        expect(e.message).to include('No se encontró definición de precio')
      end
    end
  end
end
