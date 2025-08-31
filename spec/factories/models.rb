FactoryBot.define do
  factory :category, class: Model::Category do
    sequence(:id) { |n| n }
    sequence(:code) { |n| "CAT#{n}" }
    sequence(:name) { |n| "Category #{n}" }
  end

  factory :rental_location, class: Model::RentalLocation do
    sequence(:id) { |n| n }
    sequence(:name) { |n| "Location #{n}" }
  end

  factory :rate_type, class: Model::RateType do
    sequence(:id) { |n| n }
    sequence(:name) { |n| "Rate Type #{n}" }
  end

  factory :season_definition, class: Model::SeasonDefinition do
    sequence(:id) { |n| n }
    sequence(:name) { |n| "Season Definition #{n}" }
  end

  factory :season, class: Model::Season do
    sequence(:id) { |n| n }
    sequence(:name) { |n| "Season #{n}" }
    association :season_definition, factory: :season_definition
  end

  factory :price_definition, class: Model::PriceDefinition do
    sequence(:id) { |n| n }
    sequence(:name) { |n| "Price Definition #{n}" }
    type { :season }
    association :rate_type, factory: :rate_type
    association :season_definition, factory: :season_definition
    excess { 10.0 }
    deposit { 100.0 }
    time_measurement_days { true }
    time_measurement_hours { false }
    time_measurement_minutes { false }
    time_measurement_months { false }
    units_management_days { :unitary }
    units_management_hours { :unitary }
    units_management_minutes { :unitary }
    units_management_value_days_list { '1,2,4,7' }
    units_management_value_hours_list { '1' }
    units_management_value_minutes_list { '1' }
    units_value_limit_hours_day { 0 }
    units_value_limit_min_hours { 0 }
    apply_price_by_kms { false }
  end

  factory :category_rental_location_rate_type, class: Model::CategoryRentalLocationRateType do
    sequence(:id) { |n| n }
    association :category, factory: :category
    association :rental_location, factory: :rental_location
    association :rate_type, factory: :rate_type
    association :price_definition, factory: :price_definition
  end

  factory :price, class: Model::Price do
    sequence(:id) { |n| n }
    time_measurement { :days }
    units { 1 }
    price { 25.50 }
    included_km { 0 }
    extra_km_price { 0.0 }
    association :price_definition, factory: :price_definition
    association :season, factory: :season
  end
end
