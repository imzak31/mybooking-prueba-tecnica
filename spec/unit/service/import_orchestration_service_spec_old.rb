require 'spec_helper'

RSpec.describe Service::ImportOrchestrationService, unit: true do
  let(:service) { described_class.new }
  let(:csv_content) { "category_code,rental_location_name,rate_type_name,season_name,time_measurement,units,price\nA,Barcelona,Estándar,Alta,days,2,25.50\n" }
  let(:csv_file) { double('file', read: csv_content, original_filename: 'test.csv') }

  describe '#orchestrate_import' do
    context 'with valid CSV file' do
      it 'processes the import successfully' do
        # Mock the use case to return success
        mock_result = double('result', 
                            success?: true, 
                            data: { processed_count: 1, created_count: 1, updated_count: 0 },
                            message: 'Import successful')
        
        allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform).and_return(mock_result)

        result = service.orchestrate_import(csv_file)
        
        expect(result.success?).to be true
        expect(result.data[:processed_count]).to eq(1)
        expect(result.message).to include('Import successful')
      end

      it 'passes correct parameters to use case' do
        mock_use_case = double('use_case')
        allow(UseCase::Pricing::ImportPricesUseCase).to receive(:new).and_return(mock_use_case)
        
        expected_params = {
          csv_content: csv_content,
          filename: 'test.csv'
        }
        
        expect(mock_use_case).to receive(:perform).with(expected_params).and_return(
          double('result', success?: true, data: {}, message: 'Success')
        )

        service.orchestrate_import(csv_file)
      end
    end

    context 'with import errors' do
      it 'returns detailed error information' do
        mock_result = double('result', 
                            success?: false, 
                            message: 'Import failed',
                            report: {
                              summary: { total_rows: 1, failed_rows: 1, successful_rows: 0 },
                              detailed_errors: [
                                {
                                  line: 2,
                                  error: 'Price definition not found',
                                  data: { category_code: 'Z' }
                                }
                              ]
                            })
        
        allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform).and_return(mock_result)

        result = service.orchestrate_import(csv_file)
        
        expect(result.success?).to be false
        expect(result.message).to include('Import failed')
        expect(result.report[:detailed_errors]).to be_an(Array)
        expect(result.report[:detailed_errors].first[:line]).to eq(2)
      end
    end

    context 'with file processing errors' do
      it 'handles file read errors gracefully' do
        allow(csv_file).to receive(:read).and_raise(StandardError.new('File read error'))

        result = service.orchestrate_import(csv_file)
        
        expect(result.success?).to be false
        expect(result.message).to include('Error procesando archivo')
      end

      it 'handles missing filename gracefully' do
        allow(csv_file).to receive(:original_filename).and_return(nil)
        
        mock_result = double('result', success?: true, data: {}, message: 'Success')
        allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform).and_return(mock_result)

        result = service.orchestrate_import(csv_file)
        
        expect(result.success?).to be true
      end
    end

    context 'with use case exceptions' do
      it 'handles and wraps exceptions' do
        allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform)
          .and_raise(StandardError.new('Database connection error'))

        result = service.orchestrate_import(csv_file)
        
        expect(result.success?).to be false
        expect(result.message).to include('Error crítico en importación')
      end
    end
  end

  describe '#orchestrate_preview' do
    let(:preview_params) { { csv_content: csv_content, max_rows: 10 } }

    it 'generates preview successfully' do
      mock_result = double('result', 
                          success?: true, 
                          data: {
                            analysis_summary: { sample_size: 1, estimated_issues: 0 },
                            sample_analysis: [
                              { line_in_file: 2, status: 'valid', analysis: { data_summary: {} } }
                            ]
                          })
      
      allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:preview).and_return(mock_result)

      result = service.orchestrate_preview(preview_params)
      
      expect(result.success?).to be true
      expect(result.data[:analysis_summary]).to be_a(Hash)
      expect(result.data[:sample_analysis]).to be_an(Array)
    end

    it 'handles preview errors' do
      allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:preview)
        .and_raise(StandardError.new('Preview error'))

      result = service.orchestrate_preview(preview_params)
      
      expect(result.success?).to be false
      expect(result.message).to include('Error generando vista previa')
    end

    it 'validates required parameters' do
      result = service.orchestrate_preview({})
      
      expect(result.success?).to be false
      expect(result.message).to include('Contenido CSV es requerido')
    end
  end

  describe 'result object structure' do
    it 'returns properly structured success result' do
      mock_result = double('result', 
                          success?: true, 
                          data: { test: 'data' },
                          message: 'Success message')
      
      allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform).and_return(mock_result)

      result = service.orchestrate_import(csv_file)
      
      expect(result).to respond_to(:success?)
      expect(result).to respond_to(:data)
      expect(result).to respond_to(:message)
      expect(result.success?).to be true
    end

    it 'returns properly structured error result' do
      result = service.orchestrate_import(nil)
      
      expect(result).to respond_to(:success?)
      expect(result).to respond_to(:message)
      expect(result.success?).to be false
      expect(result.message).to be_a(String)
    end
  end
end
