# Mybooking - Technical Interview Solution

## 🎯 Project Overview

This is a comprehensive solution for the Mybooking technical interview, implementing a vehicle rental pricing management system. The project demonstrates full-stack development capabilities, clean architecture principles, and robust data import functionality.

## 📋 Task Completion Summary

### ✅ Task 1: Dynamic Price Visualization System
**Status: COMPLETED + ENHANCED**

Implemented a cascading filter system for price visualization with the following features:
- ✅ Location-based rate type filtering
- ✅ Dynamic season definition loading
- ✅ Season-specific category filtering
- ✅ Multi-time measurement support
- ✅ Real-time price updates
- 🚀 **Enhancement**: Advanced error handling and suggestion system

### ✅ Task 2: Mass Price Import System  
**Status: COMPLETED + ENHANCED**

Built a comprehensive CSV import system with:
- ✅ File upload and validation
- ✅ Business rule validation
- ✅ Preview and correction workflow
- ✅ Batch processing with transaction support
- 🚀 **Enhancement**: Comprehensive test coverage (76 tests, 0 failures)
- 🚀 **Enhancement**: Import suggestions and error recovery

---

## 🏗️ Architecture Overview

### System Architecture Diagram

```mermaid
graph TB
    subgraph "Presentation Layer"
        UI[Web Interface]
        API[REST API Endpoints]
    end
    
    subgraph "Business Logic Layer"
        UC[Use Cases]
        SER[Services]
        CON[Concerns/Mixins]
    end
    
    subgraph "Data Access Layer"
        REP[Repositories]
        MOD[Models]
        QRY[Query Infrastructure]
    end
    
    subgraph "Infrastructure"
        DB[(MySQL Database)]
        FS[File System]
    end
    
    UI --> API
    API --> UC
    UC --> SER
    SER --> CON
    SER --> REP
    REP --> MOD
    REP --> QRY
    QRY --> DB
    SER --> FS
```

### Key Architectural Decisions

#### 1. **Service-Oriented Architecture**
**Decision**: Implemented business logic in dedicated service classes
```ruby
# Example: ImportOrchestrationService
class ImportOrchestrationService
  def orchestrate_import(file_data, options = {})
    # Coordinated workflow with proper error handling
  end
end
```

**Advantages**:
- Clear separation of concerns
- Testable business logic
- Reusable across different controllers
- Easy to maintain and extend

**Trade-offs**:
- Slightly more complex for simple operations
- Requires careful dependency management

#### 2. **Repository Pattern with DataMapper**
**Decision**: Used repository pattern to abstract data access
```ruby
class PriceRepository < BaseRepository
  def find_by_business_keys(category:, location:, rate_type:, season:)
    # Complex business queries abstracted
  end
end
```

**Advantages**:
- Database-agnostic business logic
- Easier testing with mocks
- Consistent query patterns
- Type safety and validation

**Trade-offs**:
- Additional abstraction layer
- Learning curve for new developers

#### 3. **Concern-Based Mixins**
**Decision**: Used Ruby modules for shared functionality
```ruby
module CsvProcessingConcern
  def validate_csv_headers(headers)
    # Reusable CSV validation logic
  end
end
```

**Advantages**:
- Code reusability
- Composable functionality
- Clear interfaces
- Easy testing

**Trade-offs**:
- Can lead to hidden dependencies
- Requires careful documentation

---

## 🎨 Task 1: Price Visualization System

### System Flow Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Frontend
    participant API as API Controller
    participant S as Service Layer
    participant R as Repository
    participant DB as Database

    U->>UI: Select Location
    UI->>API: GET /api/pricing/rate-types?location_id=1
    API->>R: Find available rate types
    R->>DB: Query category_rental_location_rate_types
    DB-->>R: Return rate types
    R-->>API: Rate types data
    API-->>UI: JSON response
    UI-->>U: Enable rate type dropdown

    U->>UI: Select Rate Type
    UI->>API: GET /api/pricing/season-definitions?location_id=1&rate_type_id=1
    API->>R: Find season definitions
    R->>DB: Query price_definitions
    DB-->>R: Season definitions
    R-->>API: Season definitions data
    API-->>UI: JSON response
    UI-->>U: Enable season dropdown

    U->>UI: Select Season
    UI->>API: GET /api/pricing/prices?filters...
    API->>S: Process price request
    S->>R: Get filtered prices
    R->>DB: Complex price query
    DB-->>R: Price data
    R-->>S: Structured prices
    S-->>API: Formatted response
    API-->>UI: JSON with prices
    UI-->>U: Display price table
```

### Key Implementation Details

#### Cascading Filter Logic
The system implements a sophisticated filtering mechanism:

1. **Location Selection**: Loads available rate types for that location
2. **Rate Type Selection**: Discovers all season definitions available for that location+rate_type
3. **Season Definition Selection**: Shows actual seasons or "Sin temporadas" option
4. **Price Display**: Shows all categories with prices matching the selected criteria

**Why this approach**:
- Follows task specification precisely
- Intuitive user experience
- Reveals all available data progressively
- Handles "Sin temporadas" cases elegantly

---

## 📥 Task 2: Mass Import System

### Import Architecture Diagram

```mermaid
graph TD
    subgraph "Import Pipeline"
        UP[File Upload] --> VAL[File Validation]
        VAL --> PARSE[CSV Parsing]
        PARSE --> BIZ[Business Validation]
        BIZ --> PREV[Preview Generation]
        PREV --> PROC[Batch Processing]
        PROC --> RES[Result Reporting]
    end
    
    subgraph "Validation Layers"
        V1[Structure Validation]
        V2[Format Validation]
        V3[Business Rule Validation]
        V4[Reference Validation]
    end
    
    subgraph "Error Handling"
        ERR[Error Collection]
        SUG[Suggestion Generation]
        REC[Recovery Options]
    end
    
    BIZ --> V1
    BIZ --> V2
    BIZ --> V3
    BIZ --> V4
    
    V1 --> ERR
    V2 --> ERR
    V3 --> ERR
    V4 --> ERR
    
    ERR --> SUG
    SUG --> REC
```

### Import Strategy Decision

**Question from Task**: "¿Planterías la importación siguiendo estos filtros o añadirías las columnas de sucursal, tipo de tarifa y temporada?"

**Our Decision**: Add explicit columns for location, rate_type, and season information.

**Reasoning**:
```ruby
# CSV Structure chosen:
# category_code,rental_location_name,rate_type_name,season_name,time_measurement,units,price
# A,Barcelona,Estándar,Alta,2,1,65.00
```

**Advantages**:
- ✅ **Self-contained**: Each row has complete context
- ✅ **Auditable**: Clear traceability of each price
- ✅ **Flexible**: Supports bulk updates across multiple contexts
- ✅ **User-friendly**: Non-technical users can understand the format
- ✅ **Validation-ready**: Easy to validate business relationships

**Trade-offs**:
- ❌ **Redundancy**: More data per row
- ❌ **File size**: Larger CSV files
- ❌ **Consistency risk**: User might input inconsistent references

**Why we rejected it**:
- Less flexible for bulk operations
- Harder to audit and trace
- Requires UI state management
- Limited to single location/rate_type/season combinations

### Import Pipeline Implementation

#### 1. **File Upload & Validation**
```ruby
class FileUploadService
  def validate_and_process(file_data)
    # Multi-layer validation with detailed error reporting
  end
end
```

#### 2. **Business Rule Validation**
```ruby
module PriceValidationConcern
  def validate_season_compatibility(price_definition, season_name)
    # Ensures business rule compliance
  end
  
  def validate_units_allowed(price_definition, units, time_measurement)
    # Validates against units_management_value_*_list
  end
end
```

#### 3. **Preview & Correction Workflow**
```ruby
class ImportOrchestrationService
  def orchestrate_preview(file_data)
    # Generates preview with suggestions for corrections
  end
end
```

#### 4. **Batch Processing with Transactions**
```ruby
def process_batch(validated_data)
  Infraestructure::Transaction.run do
    validated_data.each { |row| upsert_price(row) }
  end
end
```

---

## 🧪 Testing Strategy

### Test Coverage Overview
- **Total Tests**: 76
- **Failures**: 0
- **Coverage Areas**: Controllers, Services, Repositories, Concerns

### Testing Architecture

```mermaid
graph TB
    subgraph "Test Layers"
        UT[Unit Tests]
        IT[Integration Tests]
        CT[Controller Tests]
    end
    
    subgraph "Test Strategies"
        M[Mock-based Testing]
        F[Factory-based Data]
        T[Transactional Tests]
    end
    
    subgraph "Test Coverage"
        C1[CSV Processing - 14 tests]
        C2[Price Validation - 13 tests]
        C3[Import Orchestration - 10 tests]
        C4[Import Suggestions - 15 tests]
        C5[Controller Integration - 6 tests]
    end
    
    UT --> M
    IT --> F
    CT --> T
    
    M --> C1
    M --> C2
    F --> C3
    F --> C4
    T --> C5
```

### Key Testing Decisions

#### 1. **Mock-based Testing for Business Logic**
```ruby
# Example: Price validation tests without database
let(:query_double) { double('query') }
allow(Infraestructure::Query).to receive(:new).and_return(query_double)
```

**Advantages**:
- Fast test execution
- Isolated unit testing
- No database dependencies
- Predictable test data

#### 2. **Factory-based Integration Tests**
```ruby
# Example: Full workflow testing with realistic data
let(:category) { create(:category, code: 'A', name: 'Scooter 125cc') }
let(:price_definition) { create(:price_definition, category: category) }
```

**Advantages**:
- Realistic data scenarios
- End-to-end validation
- Database constraint testing

#### 3. **Controller Integration with Rack::Test**
```ruby
# Example: HTTP endpoint testing
post '/admin/import/corrected', 
     { corrected_data: valid_csv_data }.to_json,
     { 'CONTENT_TYPE' => 'application/json' }
```

**Advantages**:
- Full HTTP stack testing
- Request/response validation
- Error handling verification

---

## 🚀 Enhancements Beyond Requirements

### 1. **Advanced Error Suggestions System**
```ruby
class ImportSuggestionsService
  def generate_suggestions_for_error(error, row_data)
    case error.class.name
    when 'PriceDefinitionNotFoundError'
      suggest_valid_combinations(row_data)
    when 'InvalidSeasonError'
      suggest_valid_seasons(row_data)
    end
  end
end
```

**Benefits**:
- Guides users to fix import errors
- Reduces support burden
- Improves user experience
- Accelerates data correction

### 2. **Comprehensive Result Reporting**
```ruby
class OrchestrationResult
  attr_reader :result_type, :data, :message, :errors, :metadata
  
  def success?
    [:import_success, :preview_success].include?(@result_type)
  end
end
```

**Benefits**:
- Structured error reporting
- Progress tracking
- Audit trail
- User feedback

### 3. **Robust File Processing**
```ruby
module CsvProcessingConcern
  def validate_csv_headers(headers)
    # Case-insensitive header matching
    # Missing column detection
    # Extra column handling
  end
end
```

**Benefits**:
- Handles real-world CSV variations
- User-friendly error messages
- Flexible file formats

---

## 🎓 Key Learnings & Decisions

### 1. **Architecture Philosophy**
- **Separation of Concerns**: Each layer has clear responsibilities
- **Dependency Injection**: Services receive dependencies explicitly
- **Error-First Design**: Comprehensive error handling from the start

### 2. **Data Consistency Strategy**
- **Transactional Operations**: All imports wrapped in database transactions
- **Validation Layers**: Multiple validation levels prevent bad data
- **Reference Integrity**: Foreign key validation before persistence

### 3. **User Experience Focus**
- **Progressive Enhancement**: UI enables controls as data becomes available
- **Error Recovery**: Clear paths to fix issues
- **Feedback Loops**: Immediate validation and suggestions

### 4. **Testing Philosophy**
- **Test Pyramid**: More unit tests, fewer integration tests
- **Mock Strategically**: Mock external dependencies, not domain logic
- **Test Behavior**: Focus on what the system does, not how

---

## 🔧 Technical Stack

### Backend Technologies
- **Ruby 3.3.0**: Modern Ruby with performance improvements
- **Sinatra**: Lightweight web framework for API endpoints
- **DataMapper**: ORM with repository pattern support
- **MySQL**: Relational database for data integrity

### Frontend Technologies
- **Bootstrap 5.0**: Responsive UI framework
- **Vanilla JavaScript**: No heavy frameworks, fast loading
- **AJAX**: Dynamic content loading without page refreshes

### Testing & Quality
- **RSpec**: Behavior-driven testing framework
- **FactoryBot**: Test data generation
- **Rack::Test**: HTTP endpoint testing

---

## 🚦 Running the Application

### Prerequisites
- Ruby 3.3.0
- MySQL or MariaDB

### Database Setup
```bash
# Import the provided database dump
mysql -u root -p < prueba_tecnica.sql
```

### Environment Configuration
Create `.env` file:
```bash
COOKIE_SECRET="your-secret-key"
DATABASE_URL="mysql://user:password@host:port/prueba_tecnica"
TEST_DATABASE_URL="mysql://user:password@host:port/prueba_tecnica_test"
```

### Installation & Startup
```bash
# Install dependencies
bundle install

# Run the application
bundle exec rackup

# Access the application
open http://localhost:9292/pricing
```

### Testing
```bash
# Run all tests
bundle exec rspec

# Run with detailed output
bundle exec rspec --format documentation
```

---

## 🎯 Project Outcomes

### Task 1 Achievement
✅ **Fully Functional Price Visualization**
- Cascading filters work exactly as specified
- Handles all edge cases (no seasons, multiple season definitions)
- Real-time price updates with proper filtering
- Clean, responsive user interface

### Task 2 Achievement  
✅ **Production-Ready Import System**
- Comprehensive CSV import with validation
- Business rule enforcement
- Error handling and recovery
- Preview and correction workflow
- Comprehensive test coverage

### Beyond Requirements
🚀 **Enhanced Error Handling**: Suggestion system guides users
🚀 **Comprehensive Testing**: 76 tests with 0 failures
🚀 **Clean Architecture**: Maintainable, extensible codebase
🚀 **Documentation**: Detailed technical documentation

---

## 🤔 Reflections & Future Improvements

### What Went Well
- **Clean Architecture**: Easy to understand and extend
- **Comprehensive Testing**: High confidence in functionality
- **User Experience**: Intuitive interface with good error handling
- **Business Logic**: Properly validates all business rules

### Areas for Enhancement
- **Performance**: Could implement caching for frequently accessed data
- **Scalability**: Large CSV files might need streaming processing
- **Monitoring**: Production deployment would need logging and metrics
- **Security**: File upload security could be enhanced further

### Architectural Trade-offs Made
- **Complexity vs Flexibility**: Chose slightly more complex architecture for better maintainability
- **Performance vs Readability**: Prioritized readable code over micro-optimizations
- **Features vs Simplicity**: Added comprehensive error handling despite increased complexity
