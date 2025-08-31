require 'spec_helper'

RSpec.describe Service::ImportOrchestrationService, unit: true do
  let(:file_upload_service) { double('FileUploadService') }
  let(:import_use_case) { double('Impor        expect(result.result_type).to eq(:preview_success)UseCase') }
  let(:logger) { Logger.new(StringIO.new) }
  let(:service) { described_class.new(file_upload_service, import_use_case, logger) }
  
  let(:upload_params) { { file: double('uploaded_file', original_filename: 'test.csv') } }
  let(:file_info) { { temp_file_path: '/tmp/test.csv', original_filename: 'test.csv' } }

  describe '#orchestrate_import' do
    context 'with valid CSV file' do
      it 'processes the import successfully' do
        # Mock file upload service
        allow(file_upload_service).to receive(:process_uploaded_file)
          .with(upload_params)
          .and_return(file_info)
        
        allow(file_upload_service).to receive(:validate_file_for_import)
          .with(file_info[:temp_file_path])
        
        allow(file_upload_service).to receive(:cleanup_temp_file)
          .with(file_info[:temp_file_path])
        
        # Mock successful import use case
        import_result = double('ImportResult',
                              success?: true,
                              data: { processed_count: 1, created_count: 1, updated_count: 0 },
                              message: 'Import successful',
                              errors: [],
                              report: { processed_count: 1, created_count: 1, updated_count: 0 })
        
        allow(import_use_case).to receive(:perform)
          .with(csv_file_path: file_info[:temp_file_path])
          .and_return(import_result)

        result = service.orchestrate_import(upload_params)
        
        expect(result.success?).to be true
        expect(result.result_type).to eq(:import_success)
        expect(result.data).to include(processed_count: 1)
        expect(result.message).to eq('Import successful')
      end

      it 'passes correct parameters to use case' do
        # Mock file upload service
        allow(file_upload_service).to receive(:process_uploaded_file)
          .with(upload_params)
          .and_return(file_info)
        
        allow(file_upload_service).to receive(:validate_file_for_import)
          .with(file_info[:temp_file_path])
        
        allow(file_upload_service).to receive(:cleanup_temp_file)
          .with(file_info[:temp_file_path])
        
        import_result = double('ImportResult',
                              success?: true,
                              data: {},
                              message: 'Success',
                              errors: [],
                              report: {})
        
        expect(import_use_case).to receive(:perform)
          .with(csv_file_path: file_info[:temp_file_path])
          .and_return(import_result)

        service.orchestrate_import(upload_params)
      end
    end

    context 'with import errors' do
      it 'returns detailed error information' do
        # Mock file upload service
        allow(file_upload_service).to receive(:process_uploaded_file)
          .with(upload_params)
          .and_return(file_info)
        
        allow(file_upload_service).to receive(:validate_file_for_import)
          .with(file_info[:temp_file_path])
        
        allow(file_upload_service).to receive(:cleanup_temp_file)
          .with(file_info[:temp_file_path])
        
        # Mock failed import use case
        import_result = double('ImportResult',
                              success?: false,
                              data: { processed_count: 1, created_count: 0, updated_count: 0 },
                              message: 'Import failed',
                              errors: [{ line: 1, error: 'Invalid data' }],
                              report: { 
                                processed_count: 1, 
                                created_count: 0, 
                                updated_count: 0, 
                                detailed_errors: [{ line: 1, error: 'Invalid data' }]
                              })
        
        allow(import_use_case).to receive(:perform)
          .with(csv_file_path: file_info[:temp_file_path])
          .and_return(import_result)

        result = service.orchestrate_import(upload_params)
        
        expect(result.success?).to be false
        expect(result.result_type).to eq(:import_error)
        expect(result.errors).to be_present
        expect(result.message).to eq('Import failed')
      end
    end

    context 'with file processing errors' do
      it 'handles file read errors gracefully' do
        allow(file_upload_service).to receive(:process_uploaded_file)
          .with(upload_params)
          .and_raise(StandardError, 'File read error')

        result = service.orchestrate_import(upload_params)
        
        expect(result.success?).to be false
        expect(result.result_type).to eq(:critical_error)
        expect(result.message).to include('Error interno del servidor')
      end

      it 'handles file validation errors gracefully' do
        allow(file_upload_service).to receive(:process_uploaded_file)
          .with(upload_params)
          .and_return(file_info)
        
        allow(file_upload_service).to receive(:validate_file_for_import)
          .with(file_info[:temp_file_path])
          .and_raise(StandardError, 'Invalid file format')
        
        allow(file_upload_service).to receive(:cleanup_temp_file)
          .with(file_info[:temp_file_path])

        result = service.orchestrate_import(upload_params)
        
        expect(result.success?).to be false
        expect(result.result_type).to eq(:critical_error)
        expect(result.message).to include('Error interno del servidor')
      end
    end

    context 'with use case exceptions' do
      it 'handles and wraps exceptions' do
        allow(file_upload_service).to receive(:process_uploaded_file)
          .with(upload_params)
          .and_return(file_info)
        
        allow(file_upload_service).to receive(:validate_file_for_import)
          .with(file_info[:temp_file_path])
        
        allow(file_upload_service).to receive(:cleanup_temp_file)
          .with(file_info[:temp_file_path])
        
        allow(import_use_case).to receive(:perform)
          .with(csv_file_path: file_info[:temp_file_path])
          .and_raise(StandardError, 'Database connection error')

        result = service.orchestrate_import(upload_params)
        
        expect(result.success?).to be false
        expect(result.result_type).to eq(:critical_error)
        expect(result.message).to include('Error interno del servidor')
      end
    end
  end

  describe '#orchestrate_preview' do
    it 'generates preview successfully' do
      allow(file_upload_service).to receive(:process_uploaded_file)
        .with(upload_params)
        .and_return(file_info)
      
      allow(file_upload_service).to receive(:validate_file_for_import)
        .with(file_info[:temp_file_path])
      
      allow(file_upload_service).to receive(:cleanup_temp_file)
        .with(file_info[:temp_file_path])
      
      preview_result = double('PreviewResult',
                             success?: true,
                             data: { preview_rows: [{ category_code: 'A' }] },
                             message: 'Preview generated')
      
      allow(import_use_case).to receive(:preview)
        .with(csv_file_path: file_info[:temp_file_path], max_preview_rows: 10)
        .and_return(preview_result)

      result = service.orchestrate_preview(upload_params, max_rows: 10)
      
      expect(result.success?).to be true
      expect(result.result_type).to eq(:preview_success)
      expect(result.data).to include(preview_rows: [{ category_code: 'A' }])
    end

    it 'handles preview errors' do
      allow(file_upload_service).to receive(:process_uploaded_file)
        .with(upload_params)
        .and_raise(StandardError, 'Preview error')

      result = service.orchestrate_preview(upload_params)
      
      expect(result.success?).to be false
      expect(result.message).to include('Error interno en preview')
    end

    it 'validates required parameters' do
      allow(file_upload_service).to receive(:process_uploaded_file)
        .with(nil)
        .and_raise(StandardError, 'Parámetros requeridos')

      result = service.orchestrate_preview(nil)
      
      expect(result.success?).to be false
      expect(result.message).to include('Error interno en preview')
    end
  end

  describe 'result object structure' do
    it 'returns properly structured success result' do
      allow(file_upload_service).to receive(:process_uploaded_file).and_return(file_info)
      allow(file_upload_service).to receive(:validate_file_for_import)
      allow(file_upload_service).to receive(:cleanup_temp_file)
      
      import_result = double('ImportResult',
                            success?: true,
                            data: { processed_count: 1 },
                            message: 'Success',
                            errors: [],
                            report: { processed_count: 1 })
      
      allow(import_use_case).to receive(:perform).and_return(import_result)

      result = service.orchestrate_import(upload_params)
      
      expect(result).to respond_to(:success?)
      expect(result).to respond_to(:result_type)
      expect(result).to respond_to(:data)
      expect(result).to respond_to(:message)
      expect(result).to respond_to(:errors)
      expect(result).to respond_to(:metadata)
    end

    it 'returns properly structured error result' do
      allow(file_upload_service).to receive(:process_uploaded_file)
        .and_raise(StandardError, 'Test error')

      result = service.orchestrate_import(upload_params)
      
      expect(result.success?).to be false
      expect(result.result_type).to be_present
      expect(result.message).to be_present
      expect(result.errors).to be_present
    end
  end
end
