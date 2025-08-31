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
  
  describe '#validate_csv_headers' do
    it 'validates required headers successfully' do
      headers = ['category_code', 'rental_location_name', 'rate_type_name', 'season_name', 'time_measurement', 'units', 'price']
      
      result = service.validate_csv_headers(headers)
      
      expect(result).to be_a(Hash)
      expect(result['category_code']).to eq(0)
      expect(result['rental_location_name']).to eq(1)
      expect(result['rate_type_name']).to eq(2)
    end

    it 'raises error for missing required columns' do
      headers = ['category_code', 'rental_location_name']

      expect {
        service.validate_csv_headers(headers)
      }.to raise_error(Service::Concerns::CsvProcessingConcern::InvalidHeaderError, /Columnas requeridas faltantes/)
    end

    it 'handles case-insensitive headers' do
      headers = ['CATEGORY_CODE', 'Rental_Location_Name', 'RATE_TYPE_NAME', 'season_name', 'time_measurement', 'units', 'price']
      
      result = service.validate_csv_headers(headers)
      
      expect(result).to be_a(Hash)
      expect(result['category_code']).to eq(0)
    end

    it 'includes optional columns in mapping' do
      headers = ['category_code', 'rental_location_name', 'rate_type_name', 'season_name', 'time_measurement', 'units', 'price', 'included_km', 'extra_km_price']
      
      result = service.validate_csv_headers(headers)
      
      expect(result['included_km']).to eq(7)
      expect(result['extra_km_price']).to eq(8)
    end
  end

  describe '#process_csv_row' do
    let(:column_mapping) do
      {
        'category_code' => 0,
        'rental_location_name' => 1,
        'rate_type_name' => 2,
        'season_name' => 3,
        'time_measurement' => 4,
        'units' => 5,
        'price' => 6
      }
    end

    it 'processes valid row successfully' do
      row_data = ['A', 'Barcelona', 'Estándar', 'Alta', 'days', '2', '25.50']
      
      result = service.process_csv_row(row_data, column_mapping, 1)
      
      expect(result[:success]).to be true
      expect(result[:data][:category_code]).to eq('A')
      expect(result[:data][:rental_location_name]).to eq('Barcelona')
      expect(result[:line]).to eq(1)
    end

    it 'handles validation errors gracefully' do
      invalid_row_data = ['', 'Barcelona', 'Estándar', 'Alta', 'days', '2', '25.50']
      
      result = service.process_csv_row(invalid_row_data, column_mapping, 2)
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Campo requerido vacío')
      expect(result[:line]).to eq(2)
    end

    it 'validates required fields' do
      row_data = ['A', '', 'Estándar', 'Alta', 'days', '2', '25.50']
      
      result = service.process_csv_row(row_data, column_mapping, 3)
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Campo requerido vacío: rental_location_name')
    end

    it 'validates price format' do
      row_data = ['A', 'Barcelona', 'Estándar', 'Alta', 'days', '2', 'invalid_price']
      
      result = service.process_csv_row(row_data, column_mapping, 4)
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Formato de precio inválido')
    end

    it 'validates units format' do
      row_data = ['A', 'Barcelona', 'Estándar', 'Alta', 'days', 'invalid_units', '25.50']
      
      result = service.process_csv_row(row_data, column_mapping, 5)
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Formato de unidades inválido')
    end

    it 'validates time measurement' do
      row_data = ['A', 'Barcelona', 'Estándar', 'Alta', 'invalid_time', '2', '25.50']
      
      result = service.process_csv_row(row_data, column_mapping, 6)
      
      expect(result[:success]).to be false
      expect(result[:error]).to include('Medición de tiempo inválida')
    end
  end

  describe '#validate_price_format' do
    it 'validates positive prices' do
      result = service.validate_price_format('25.50')
      expect(result).to eq(25.50)
    end

    it 'cleans price format with commas' do
      result = service.validate_price_format('1,025.50')
      expect(result).to eq(1025.50)
    end

    it 'handles blank prices' do
      result = service.validate_price_format('')
      expect(result).to be_nil
    end

    it 'raises error for negative prices' do
      expect {
        service.validate_price_format('-25.50')
      }.to raise_error(Service::Concerns::CsvProcessingConcern::InvalidRowDataError, /no puede ser negativo/)
    end

    it 'raises error for invalid format' do
      expect {
        service.validate_price_format('abc')
      }.to raise_error(Service::Concerns::CsvProcessingConcern::InvalidRowDataError, /Formato de precio inválido/)
    end
  end

  describe '#validate_units_format' do
    it 'validates positive units' do
      result = service.validate_units_format('5')
      expect(result).to eq(5)
    end

    it 'handles blank units' do
      result = service.validate_units_format('')
      expect(result).to be_nil
    end

    it 'raises error for zero or negative units' do
      expect {
        service.validate_units_format('0')
      }.to raise_error(Service::Concerns::CsvProcessingConcern::InvalidRowDataError, /deben ser positivas/)
    end

    it 'raises error for invalid format' do
      expect {
        service.validate_units_format('abc')
      }.to raise_error(Service::Concerns::CsvProcessingConcern::InvalidRowDataError, /Formato de unidades inválido/)
    end
  end

  describe '#generate_import_report' do
    it 'generates comprehensive report' do
      results = [
        { success: true, result: { action: :created } },
        { success: true, result: { action: :updated } },
        { success: false, error: 'Campo requerido vacío: category_code', line: 3 },
        { success: false, error: 'Formato de precio inválido: abc', line: 4 }
      ]

      report = service.generate_import_report(results)

      expect(report[:summary][:total_rows]).to eq(4)
      expect(report[:summary][:successful_rows]).to eq(2)
      expect(report[:summary][:failed_rows]).to eq(2)
      expect(report[:summary][:created_prices]).to eq(1)
      expect(report[:summary][:updated_prices]).to eq(1)
      expect(report[:summary][:success_rate]).to eq(50.0)
      
      expect(report[:errors_by_type]).to include(
        'Campos requeridos faltantes' => 1,
        'Formato de precio inválido' => 1
      )
      
      expect(report[:detailed_errors]).to be_an(Array)
      expect(report[:timestamp]).to be_a(Time)
    end
  end
end
