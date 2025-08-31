require 'rake'

require_relative 'config/application'

task :basic_environment do
  desc "Basic environment"
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = Encoding::UTF_8
end

namespace :foo do
  desc "Foo task"
  task :bar do
    puts "Foo bar"
  end
end

namespace :pricing do
  desc "Import prices from CSV file"
  task :import, [:csv_file_path] => :basic_environment do |task, args|
    unless args.csv_file_path
      puts "Usage: bundle exec rake pricing:import[/path/to/file.csv]"
      exit 1
    end

    csv_file_path = args.csv_file_path

    unless File.exist?(csv_file_path)
      puts "Error: File not found - #{csv_file_path}"
      exit 1
    end

    puts "Starting price import from: #{csv_file_path}"
    puts "Timestamp: #{Time.now}"
    puts "-" * 50

    # Initialize services
    import_service = Service::PriceImportService.new(Logger.new(STDOUT))
    use_case = UseCase::Pricing::ImportPricesUseCase.new(import_service, Logger.new(STDOUT))

    # Execute import
    result = use_case.perform(csv_file_path: csv_file_path)

    # Display results
    if result.success?
      puts "\n✅ IMPORT SUCCESSFUL"
      puts "Processed: #{result.data[:processed_count]} prices"
      puts "Created: #{result.data[:created_count]} new prices"
      puts "Updated: #{result.data[:updated_count]} existing prices"
    else
      puts "\n❌ IMPORT FAILED"
      puts "Error: #{result.message}"
      
      if result.report && result.report[:summary]
        puts "Summary:"
        puts "  Total rows: #{result.report[:summary][:total_rows]}"
        puts "  Successful: #{result.report[:summary][:successful_rows]}"
        puts "  Failed: #{result.report[:summary][:failed_rows]}"
        puts "  Success rate: #{result.report[:summary][:success_rate]}%"
        
        if result.report[:errors_by_type]&.any?
          puts "\nError breakdown:"
          result.report[:errors_by_type].each do |error_type, count|
            puts "  #{error_type}: #{count}"
          end
        end
        
        if result.report[:detailed_errors]&.any?
          puts "\nFirst few errors:"
          result.report[:detailed_errors].first(3).each_with_index do |error, index|
            puts "  #{index + 1}. Line #{error[:line]}: #{error[:error]}"
          end
        end
      end
    end

    puts "-" * 50
    puts "Import completed at: #{Time.now}"
  end

  desc "Preview CSV import without executing"
  task :preview, [:csv_file_path, :max_rows] => :basic_environment do |task, args|
    unless args.csv_file_path
      puts "Usage: bundle exec rake pricing:preview[/path/to/file.csv,10]"
      exit 1
    end

    csv_file_path = args.csv_file_path
    max_rows = (args.max_rows || 10).to_i

    unless File.exist?(csv_file_path)
      puts "Error: File not found - #{csv_file_path}"
      exit 1
    end

    puts "Previewing import from: #{csv_file_path}"
    puts "Max rows to analyze: #{max_rows}"
    puts "-" * 50

    # Initialize services
    import_service = Service::PriceImportService.new(Logger.new(STDOUT))
    use_case = UseCase::Pricing::ImportPricesUseCase.new(import_service, Logger.new(STDOUT))

    # Execute preview
    result = use_case.preview(
      csv_file_path: csv_file_path,
      max_preview_rows: max_rows
    )

    if result.success?
      preview_data = result.data
      
      puts "📋 PREVIEW RESULTS"
      puts "Sample size: #{preview_data[:total_sample_size]} rows"
      puts "Estimated issues: #{preview_data[:estimated_issues]} rows"
      
      if preview_data[:sample_rows]&.any?
        puts "\nSample analysis:"
        preview_data[:sample_rows].each_with_index do |row_result, index|
          status = row_result[:success] ? "✅" : "❌"
          line_info = row_result[:line] ? " (Line #{row_result[:line]})" : ""
          
          if row_result[:success]
            category = row_result.dig(:data, :category_code)
            location = row_result.dig(:data, :rental_location_name)
            puts "  #{status} #{index + 1}#{line_info}: #{category} at #{location}"
          else
            puts "  #{status} #{index + 1}#{line_info}: #{row_result[:error]}"
          end
        end
      end
      
      success_rate = preview_data[:total_sample_size] > 0 ? 
        ((preview_data[:total_sample_size] - preview_data[:estimated_issues]).to_f / preview_data[:total_sample_size] * 100).round(2) : 0
      
      puts "\nEstimated success rate: #{success_rate}%"
      
      if success_rate < 80
        puts "\n⚠️  WARNING: Low success rate detected. Review errors before importing."
      elsif success_rate >= 95
        puts "\n🎉 Excellent! File looks ready for import."
      end
      
    else
      puts "❌ PREVIEW FAILED"
      puts "Error: #{result.message}"
    end

    puts "-" * 50
  end
end
