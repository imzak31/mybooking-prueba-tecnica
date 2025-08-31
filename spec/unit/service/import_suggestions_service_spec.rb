require 'spec_helper'

RSpec.describe Service::ImportSuggestionsService, unit: true do
  let(:service) { described_class.new }
  
  # Create test data
  let!(:category_a) { create(:category, code: 'A', name: 'Scooter 125cc') }
  let!(:category_b) { create(:category, code: 'B', name: 'Turismo') }
  let!(:rental_location_bcn) { create(:rental_location, name: 'Barcelona') }
  let!(:rental_location_mnc) { create(:rental_location, name: 'Menorca') }
  let!(:rate_type_std) { create(:rate_type, name: 'Estándar') }
  let!(:rate_type_premium) { create(:rate_type, name: 'Premium') }
  
  let!(:season_definition) { create(:season_definition, name: 'Temporadas scooters') }
  let!(:season_alta) { create(:season, name: 'Alta', season_definition: season_definition) }
  let!(:season_baja) { create(:season, name: 'Baja', season_definition: season_definition) }
  
  let!(:price_definition_a) do
    create(:price_definition, 
           name: 'A - Barcelona - Estándar',
           rate_type: rate_type_std,
           season_definition: season_definition,
           units_management_value_days_list: '1,2,4,15')
  end
  
  let!(:price_definition_b) do
    create(:price_definition,
           name: 'B - Barcelona - Estándar', 
           rate_type: rate_type_std,
           season_definition: season_definition,
           units_management_value_days_list: '1,2,4,8,15,30')
  end
  
  let!(:crlrt_a) do
    create(:category_rental_location_rate_type,
           category: category_a,
           rental_location: rental_location_bcn,
           rate_type: rate_type_std,
           price_definition: price_definition_a)
  end
  
  let!(:crlrt_b) do
    create(:category_rental_location_rate_type,
           category: category_b,
           rental_location: rental_location_bcn,
           rate_type: rate_type_std,
           price_definition: price_definition_b)
  end

  describe '#get_valid_options' do
    let(:options) { service.get_valid_options }

    it 'returns a hash with all valid options' do
      expect(options).to be_a(Hash)
      expect(options.keys).to match_array([:categories, :rental_locations, :rate_types, :seasons, :units, :time_measurements])
    end

    it 'includes all categories' do
      categories = options[:categories]
      expect(categories).to be_an(Array)
      expect(categories.length).to eq(2)
      
      category_codes = categories.map { |c| c[:code] }
      expect(category_codes).to include('A', 'B')
    end

    it 'includes all rental locations' do
      locations = options[:rental_locations]
      expect(locations).to be_an(Array)
      expect(locations.length).to eq(2)
      
      location_names = locations.map { |l| l[:name] }
      expect(location_names).to include('Barcelona', 'Menorca')
    end

    it 'includes all rate types' do
      rate_types = options[:rate_types]
      expect(rate_types).to be_an(Array)
      expect(rate_types.length).to eq(2)
      
      rate_type_names = rate_types.map { |r| r[:name] }
      expect(rate_type_names).to include('Estándar', 'Premium')
    end

    it 'includes seasons grouped by definition' do
      seasons = options[:seasons]
      expect(seasons).to be_a(Hash)
      expect(seasons['Temporadas scooters']).to include('Alta', 'Baja')
    end

    it 'includes units grouped by category' do
      units = options[:units]
      expect(units).to be_a(Hash)
      expect(units['A']).to eq([1, 2, 4, 15])
      expect(units['B']).to eq([1, 2, 4, 8, 15, 30])
    end

    it 'includes time measurements' do
      time_measurements = options[:time_measurements]
      expect(time_measurements).to eq(['days', 'hours', 'minutes', 'months'])
    end
  end

  describe '#generate_suggestions_for_error' do
    context 'for price definition not found error' do
      let(:error_data) do
        {
          'category_code' => 'Z',
          'rental_location_name' => 'Madrid', 
          'rate_type_name' => 'VIP'
        }
      end
      let(:error_message) { 'Definición de precio no encontrada' }
      
      it 'generates suggestions for invalid values' do
        suggestions = service.generate_suggestions_for_error(error_data, error_message)
        
        expect(suggestions).to be_an(Array)
        expect(suggestions.any? { |s| s.include?('Cambiar categoría') }).to be true
        expect(suggestions.any? { |s| s.include?('Cambiar sucursal') }).to be true
        expect(suggestions.any? { |s| s.include?('Cambiar tipo tarifa') }).to be true
      end
    end

    context 'for invalid season error' do
      let(:error_data) do
        {
          'category_code' => 'A',
          'season_name' => 'Primavera'
        }
      end
      let(:error_message) { 'Temporada inválida' }
      
      it 'generates season suggestions' do
        suggestions = service.generate_suggestions_for_error(error_data, error_message)
        
        expect(suggestions).to be_an(Array)
        expect(suggestions.any? { |s| s.include?('Temporadas válidas') }).to be true
      end
    end

    context 'for invalid units error' do
      let(:error_data) do
        {
          'category_code' => 'A',
          'units' => '10'
        }
      end
      let(:error_message) { 'Unidades no permitidas' }
      
      it 'generates units suggestions' do
        suggestions = service.generate_suggestions_for_error(error_data, error_message)
        
        expect(suggestions).to be_an(Array)
        expect(suggestions.any? { |s| s.include?('Unidades válidas') }).to be true
        expect(suggestions.any? { |s| s.include?('Sugerencia') }).to be true
      end
    end

    context 'for invalid price error' do
      let(:error_data) { { 'price' => 'abc' } }
      let(:error_message) { 'Precio inválido' }
      
      it 'generates price suggestions' do
        suggestions = service.generate_suggestions_for_error(error_data, error_message)
        
        expect(suggestions).to be_an(Array)
        expect(suggestions.any? { |s| s.include?('número válido') }).to be true
        expect(suggestions.any? { |s| s.include?('punto decimal') }).to be true
      end
    end
  end

  describe 'caching behavior' do
    it 'caches database queries for better performance' do
      # First call
      options1 = service.get_valid_options
      
      # Mock repository to ensure it's not called again
      expect_any_instance_of(Repository::CategoryRepository).not_to receive(:find_all)
      
      # Second call should use cached data
      options2 = service.get_valid_options
      
      expect(options1).to eq(options2)
    end
  end

  describe 'private methods' do
    describe '#find_closest_valid_unit' do
      it 'finds the closest valid unit' do
        valid_units = [1, 2, 4, 15]
        closest = service.send(:find_closest_valid_unit, 3, valid_units)
        expect(closest).to eq(2)
        
        closest = service.send(:find_closest_valid_unit, 10, valid_units)
        expect(closest).to eq(15)
      end

      it 'returns nil for empty units array' do
        closest = service.send(:find_closest_valid_unit, 5, [])
        expect(closest).to be_nil
      end
    end

    describe '#categorize_error' do
      it 'categorizes different error types correctly' do
        expect(service.send(:categorize_error, 'Definición de precio no encontrada')).to eq(:price_definition_not_found)
        expect(service.send(:categorize_error, 'Temporada inválida')).to eq(:invalid_season)
        expect(service.send(:categorize_error, 'Unidades no permitidas')).to eq(:invalid_units)
        expect(service.send(:categorize_error, 'Precio inválido')).to eq(:invalid_price)
        expect(service.send(:categorize_error, 'Error desconocido')).to eq(:general_error)
      end
    end
  end
end
