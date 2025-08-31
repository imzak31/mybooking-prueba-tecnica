module Service
  class FileUploadService
    
    # Errores específicos de upload
    class FileUploadError < StandardError; end
    class InvalidFileError < FileUploadError; end
    class FileSizeError < FileUploadError; end
    class FileProcessingError < FileUploadError; end

    MAX_FILE_SIZE = 10 * 1024 * 1024 # 10MB
    ALLOWED_EXTENSIONS = %w[.csv].freeze
    TEMP_DIR = '/tmp'.freeze

    def initialize(logger = nil)
      @logger = logger || Logger.new(STDOUT)
    end

    # Procesar archivo subido y retornar path temporal
    def process_uploaded_file(uploaded_file_params)
      validate_upload_params(uploaded_file_params)
      
      uploaded_file = uploaded_file_params[:tempfile]
      original_filename = uploaded_file_params[:filename]
      
      validate_file_properties(uploaded_file, original_filename)
      
      # Crear archivo temporal seguro
      temp_file_path = create_temp_file(uploaded_file, original_filename)
      
      @logger.info("Archivo procesado exitosamente: #{original_filename} -> #{temp_file_path}")
      
      {
        temp_file_path: temp_file_path,
        original_filename: original_filename,
        file_size: File.size(temp_file_path)
      }
    end

    # Limpiar archivo temporal
    def cleanup_temp_file(temp_file_path)
      return unless temp_file_path && File.exist?(temp_file_path)
      
      begin
        File.delete(temp_file_path)
        @logger.debug("Archivo temporal eliminado: #{temp_file_path}")
      rescue => e
        @logger.warn("No se pudo eliminar archivo temporal #{temp_file_path}: #{e.message}")
      end
    end

    # Validar archivo antes de procesamiento
    def validate_file_for_import(temp_file_path)
      unless File.exist?(temp_file_path)
        raise FileProcessingError, "Archivo temporal no encontrado"
      end

      # Validar que es un CSV bien formado
      begin
        CSV.foreach(temp_file_path, headers: true).first
      rescue CSV::MalformedCSVError => e
        raise InvalidFileError, "CSV malformado: #{e.message}"
      rescue => e
        raise FileProcessingError, "Error leyendo archivo: #{e.message}"
      end

      true
    end

    private

    # Validar parámetros de upload
    def validate_upload_params(upload_params)
      unless upload_params&.is_a?(Hash)
        raise InvalidFileError, "Parámetros de archivo inválidos"
      end

      unless upload_params[:tempfile] && upload_params[:filename]
        raise InvalidFileError, "Archivo no proporcionado o incompleto"
      end
    end

    # Validar propiedades del archivo
    def validate_file_properties(uploaded_file, original_filename)
      # Validar extensión
      file_extension = File.extname(original_filename).downcase
      unless ALLOWED_EXTENSIONS.include?(file_extension)
        raise InvalidFileError, 
          "Extensión no permitida: #{file_extension}. Permitidas: #{ALLOWED_EXTENSIONS.join(', ')}"
      end

      # Validar tamaño
      file_size = uploaded_file.size
      if file_size > MAX_FILE_SIZE
        raise FileSizeError, 
          "Archivo demasiado grande: #{format_file_size(file_size)}. Máximo: #{format_file_size(MAX_FILE_SIZE)}"
      end

      if file_size == 0
        raise InvalidFileError, "Archivo vacío"
      end
    end

    # Crear archivo temporal con nombre único
    def create_temp_file(uploaded_file, original_filename)
      timestamp = Time.now.to_i
      safe_filename = sanitize_filename(original_filename)
      temp_filename = "import_#{timestamp}_#{safe_filename}"
      temp_file_path = File.join(TEMP_DIR, temp_filename)

      begin
        FileUtils.cp(uploaded_file.path, temp_file_path)
        temp_file_path
      rescue => e
        raise FileProcessingError, "Error creando archivo temporal: #{e.message}"
      end
    end

    # Sanitizar nombre de archivo
    def sanitize_filename(filename)
      # Remover caracteres peligrosos y limitar longitud
      sanitized = filename.gsub(/[^0-9A-Za-z.\-_]/, '_')
      sanitized[0..50] # Limitar a 50 caracteres
    end

    # Formatear tamaño de archivo legible
    def format_file_size(size_bytes)
      units = %w[B KB MB GB]
      unit_index = 0
      size = size_bytes.to_f

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end
  end
end
