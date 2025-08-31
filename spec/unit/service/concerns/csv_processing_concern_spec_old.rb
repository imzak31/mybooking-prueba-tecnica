require 'spec_helper'

# Test class to include the concern
class TestCSVProcessingService
  include Service::Concerns::CsvProcessingConcern
  
  def initialize
    @logger = Logger.new(StringIO.new)
  end
end

RSpec.describe Service::Concerns::CsvProcessingConcern, unit: true do
  let(:service) { TestCSVProcessingService.new }
  
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

  describe '#parse_csv_content' do
    let(:valid_csv) do
      "category_code,rental_location_name,rate_type_name,season_name,time_measurement,units,price\n" \
      "A,Barcelona,Estándar,Alta,days,2,25.50\n" \
      "A,Barcelona,Estándar,Alta,days,4,30.00\n"
    end

    it 'parses valid CSV content successfully' do
      result = service.parse_csv_content(valid_csv)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      
      first_row = result.first
      expect(first_row['category_code']).to eq('A')
      expect(first_row['rental_location_name']).to eq('Barcelona')
      expect(first_row['price']).to eq('25.50')
    end

    it 'handles CSV with BOM' do
      csv_with_bom = "\uFEFF" + valid_csv
      
      result = service.parse_csv_content(csv_with_bom)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
    end

    it 'handles empty CSV' do
      result = service.parse_csv_content("")
      
      expect(result).to be_an(Array)
      expect(result).to be_empty
    end

    it 'handles CSV with only headers' do
      headers_only = "category_code,rental_location_name,rate_type_name,season_name,time_measurement,units,price\n"
      
      result = service.parse_csv_content(headers_only)
      
      expect(result).to be_an(Array)
      expect(result).to be_empty
    end

    it 'raises error for malformed CSV' do
      malformed_csv = "category_code,rental_location_name\nA,Barcelona,ExtraColumn"
      
      expect {
        service.parse_csv_content(malformed_csv)
      }.to raise_error(Service::Concerns::CsvProcessingConcern::CsvParsingError)
    end
  end

  describe '#process_csv_row' do
    let(:valid_row_data) do
      {
        'category_code' => 'A',
        'rental_location_name' => 'Barcelona',
        'rate_type_name' => 'Estándar',
        'season_name' => 'Alta',
        'time_measurement' => 'days',
        'units' => '2',
        'price' => '25.50'
      }
    end

    it 'processes valid row successfully' do
      result = service.process_csv_row(valid_row_data, 2)
      
      expect(result[:status]).to eq(:success)
      expect(result[:data]).to be_a(Hash)
      expect(result[:data][:units]).to eq(2)
      expect(result[:data][:price]).to eq(25.50)
    end

    it 'handles validation errors gracefully' do
      invalid_row_data = valid_row_data.merge('category_code' => 'Z')
      
      result = service.process_csv_row(invalid_row_data, 2)
      
      expect(result[:status]).to eq(:error)
      expect(result[:error]).to be_a(String)
      expect(result[:data]).to eq(invalid_row_data)
    end

    it 'converts string numbers to appropriate types' do
      result = service.process_csv_row(valid_row_data, 2)
      
      expect(result[:data][:units]).to be_an(Integer)
      expect(result[:data][:price]).to be_a(Float)
    end

    it 'handles optional fields' do
      row_with_optional = valid_row_data.merge(
        'included_km' => '100',
        'extra_km_price' => '0.25'
      )
      
      result = service.process_csv_row(row_with_optional, 2)
      
      expect(result[:status]).to eq(:success)
      expect(result[:data][:included_km]).to eq(100)
      expect(result[:data][:extra_km_price]).to eq(0.25)
    end

    it 'handles empty season gracefully' do
      row_no_season = valid_row_data.merge('season_name' => '')
      
      result = service.process_csv_row(row_no_season, 2)
      
      expect(result[:status]).to eq(:success)
      expect(result[:data][:season_name]).to eq('')
    end

    it 'validates required fields' do
      incomplete_row = valid_row_data.except('price')
      
      result = service.process_csv_row(incomplete_row, 2)
      
      expect(result[:status]).to eq(:error)
      expect(result[:error]).to include('requerido')
    end
  end

  describe '#normalize_csv_data' do
    it 'converts string values to appropriate types' do
      row_data = {
        'units' => '5',
        'price' => '25.50',
        'included_km' => '100',
        'extra_km_price' => '0.25',
        'category_code' => 'A'
      }
      
      result = service.normalize_csv_data(row_data)
      
      expect(result[:units]).to eq(5)
      expect(result[:price]).to eq(25.5)
      expect(result[:included_km]).to eq(100)
      expect(result[:extra_km_price]).to eq(0.25)
      expect(result[:category_code]).to eq('A')
    end

    it 'handles nil and empty values' do
      row_data = {
        'units' => '',
        'price' => nil,
        'included_km' => '0',
        'category_code' => 'A'
      }
      
      result = service.normalize_csv_data(row_data)
      
      expect(result[:units]).to be_nil
      expect(result[:price]).to be_nil
      expect(result[:included_km]).to eq(0)
      expect(result[:category_code]).to eq('A')
    end

    it 'preserves string fields' do
      row_data = {
        'category_code' => 'A',
        'rental_location_name' => 'Barcelona',
        'rate_type_name' => 'Estándar',
        'season_name' => 'Alta',
        'time_measurement' => 'days'
      }
      
      result = service.normalize_csv_data(row_data)
      
      expect(result[:category_code]).to eq('A')
      expect(result[:rental_location_name]).to eq('Barcelona')
      expect(result[:rate_type_name]).to eq('Estándar')
      expect(result[:season_name]).to eq('Alta')
      expect(result[:time_measurement]).to eq('days')
    end
  end

  describe 'error handling' do
    it 'provides detailed error information' do
      invalid_row = {
        'category_code' => 'Z',
        'rental_location_name' => 'Madrid',
        'rate_type_name' => 'Premium'
      }
      
      result = service.process_csv_row(invalid_row, 5)
      
      expect(result[:status]).to eq(:error)
      expect(result[:line]).to eq(5)
      expect(result[:data]).to eq(invalid_row)
      expect(result[:error]).to be_a(String)
    end

    it 'handles unexpected exceptions gracefully' do
      # Force an exception by mocking
      allow(service).to receive(:validate_price_data).and_raise(StandardError.new('Unexpected error'))
      
      result = service.process_csv_row({}, 1)
      
      expect(result[:status]).to eq(:error)
      expect(result[:error]).to include('Error procesando fila')
    end
  end
end
