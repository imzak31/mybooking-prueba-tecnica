require 'securerandom'

module Controller
  module Concerns
    module ApiResponseConcern
      extend ActiveSupport::Concern

      # Respuesta JSON exitosa estándar
      def api_success_response(data, message: nil, metadata: {})
        response = {
          success: true,
          timestamp: Time.now.utc.iso8601
        }
        
        response[:message] = message if message
        response[:data] = data if data
        response[:metadata] = metadata unless metadata.empty?
        
        content_type :json
        response.to_json
      end

      # Respuesta JSON de error estándar
      def api_error_response(message, errors: [], error_code: nil, status: 400)
        response = {
          success: false,
          message: message,
          timestamp: Time.now.utc.iso8601
        }
        
        response[:error_code] = error_code if error_code
        response[:errors] = errors unless errors.empty?
        
        content_type :json
        status status
        response.to_json
      end

      # Respuesta JSON con paginación
      def api_paginated_response(data, pagination_info, message: nil)
        response = {
          success: true,
          timestamp: Time.now.utc.iso8601,
          data: data,
          pagination: {
            current_page: pagination_info[:current_page],
            per_page: pagination_info[:per_page],
            total_pages: pagination_info[:total_pages],
            total_count: pagination_info[:total_count]
          }
        }
        
        response[:message] = message if message
        
        content_type :json
        response.to_json
      end

      # Respuesta JSON para operaciones asíncronas
      def api_async_response(job_id, message: "Operación iniciada", status_url: nil)
        response = {
          success: true,
          async: true,
          job_id: job_id,
          message: message,
          timestamp: Time.now.utc.iso8601
        }
        
        response[:status_url] = status_url if status_url
        
        content_type :json
        response.to_json
      end

      # Manejar errores de validación
      def handle_validation_errors(validation_errors)
        formatted_errors = validation_errors.map do |field, messages|
          {
            field: field,
            messages: Array(messages)
          }
        end
        
        api_error_response(
          "Errores de validación encontrados",
          errors: formatted_errors,
          error_code: "validation_failed",
          status: 422
        )
      end

      # Manejar errores de autorización
      def handle_authorization_error(message = "No autorizado")
        api_error_response(
          message,
          error_code: "authorization_failed",
          status: 401
        )
      end

      # Manejar errores de recurso no encontrado
      def handle_not_found_error(resource_type = "Recurso")
        api_error_response(
          "#{resource_type} no encontrado",
          error_code: "resource_not_found",
          status: 404
        )
      end

      # Manejar errores internos del servidor
      def handle_internal_error(error, request_id: nil)
        error_details = {
          error_class: error.class.name,
          error_message: error.message
        }
        
        error_details[:request_id] = request_id if request_id
        
        # Log del error completo para debugging
        logger&.error("Internal server error: #{error.message}")
        logger&.error(error.backtrace.join("\n"))
        
        api_error_response(
          "Error interno del servidor",
          errors: [error_details],
          error_code: "internal_server_error",
          status: 500
        )
      end

      # Wrapper para ejecutar acciones con manejo de errores estándar
      def with_error_handling(request_id: nil, &block)
        begin
          yield
        rescue ArgumentError => e
          api_error_response(
            "Parámetros inválidos: #{e.message}",
            error_code: "invalid_parameters",
            status: 400
          )
        rescue StandardError => e
          handle_internal_error(e, request_id: request_id)
        end
      end

      # Generar ID de request único
      def generate_request_id
        "REQ_#{Time.now.to_i}_#{SecureRandom.hex(4).upcase}"
      end

      # Configurar headers CORS si es necesario
      def set_cors_headers
        headers(
          'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
        )
      end

      # Respuesta para preflight OPTIONS
      def handle_preflight_request
        set_cors_headers
        status 200
        ""
      end
    end
  end
end
