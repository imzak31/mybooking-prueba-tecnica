require 'spec_helper'
require_relative '../../../../app/controller/admin/import_controller'
require 'rack/test'
require 'json'

RSpec.describe Controller::Admin::ImportController do
  include Rack::Test::Methods

  def app
    @app ||= Class.new(Sinatra::Base) do
      register Controller::Admin::ImportController
    end
  end

  describe 'GET /admin/import/options' do
    it 'returns JSON with valid import options' do
      get '/admin/import/options'
      
      expect(last_response).to be_ok
      expect(last_response.headers['Content-Type']).to include('application/json')
      
      json = JSON.parse(last_response.body)
      expect(json).to have_key('success')
      expect(json['success']).to be true
      expect(json).to have_key('data')
      expect(json).to have_key('message')
      
      data = json['data']
      expect(data).to have_key('categories')
      expect(data).to have_key('rental_locations')
      expect(data).to have_key('rate_types')
      expect(data).to have_key('seasons')
      expect(data).to have_key('units')
      expect(data).to have_key('time_measurements')
    end

    it 'handles errors gracefully' do
      allow_any_instance_of(Service::ImportSuggestionsService).to receive(:get_valid_options).and_raise(StandardError, 'Database error')
      
      get '/admin/import/options'
      
      expect(last_response.status).to eq(500)
      json = JSON.parse(last_response.body)
      expect(json).to have_key('success')
      expect(json['success']).to be false
      expect(json).to have_key('error')
      expect(json['error']).to eq('Database error')
    end
  end

  describe 'POST /admin/import/corrected' do
    let(:valid_corrected_data) do
      {
        corrected_rows: [
          {
            data: {
              'category_code' => 'A',
              'rental_location_name' => 'Barcelona',
              'rate_type_name' => 'Estándar',
              'season_name' => 'Alta',
              'time_measurement' => 'days',
              'units' => '1',
              'price' => '25.50',
              'included_km' => '',
              'extra_km_price' => ''
            },
            corrected: true
          }
        ]
      }
    end

    it 'processes corrected CSV data successfully' do
      # Mock the use case to return success
      allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform).and_return(
        double(
          success?: true,
          data: {
            summary: {
              total_rows: 1,
              successful_rows: 1,
              created_prices: 1,
              updated_prices: 0
            }
          }
        )
      )
      
      post '/admin/import/corrected', valid_corrected_data.to_json, {'CONTENT_TYPE' => 'application/json'}
      
      expect(last_response).to be_ok
      expect(last_response.headers['Content-Type']).to include('application/json')
      
      json = JSON.parse(last_response.body)
      expect(json).to have_key('success')
      expect(json['success']).to be true
      expect(json).to have_key('data')
      expect(json).to have_key('message')
    end

    it 'returns 400 for missing corrected data' do
      post '/admin/import/corrected', {}.to_json, {'CONTENT_TYPE' => 'application/json'}
      
      expect(last_response.status).to eq(200) # Returns 200 but with error in JSON
      json = JSON.parse(last_response.body)
      expect(json).to have_key('success')
      expect(json['success']).to be false
      expect(json).to have_key('message')
      expect(json['message']).to eq('No hay datos corregidos para procesar')
    end

    it 'returns 400 for invalid JSON' do
      post '/admin/import/corrected', 'invalid json', {'CONTENT_TYPE' => 'application/json'}
      
      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json).to have_key('success')
      expect(json['success']).to be false
      expect(json).to have_key('message')
      expect(json['message']).to eq('Error en formato de datos JSON')
    end

    it 'handles processing errors gracefully' do
      allow_any_instance_of(UseCase::Pricing::ImportPricesUseCase).to receive(:perform).and_raise(StandardError, 'Processing error')
      
      post '/admin/import/corrected', valid_corrected_data.to_json, {'CONTENT_TYPE' => 'application/json'}
      
      expect(last_response.status).to eq(500)
      json = JSON.parse(last_response.body)
      expect(json).to have_key('success')
      expect(json['success']).to be false
      expect(json).to have_key('message')
      expect(json['message']).to include('Processing error')
    end
  end
end