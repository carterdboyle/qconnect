source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2", ">= 8.0.2.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

gem "actioncable"
gem "redis"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "ffi", "~> 1.16"

gem "stimulus-rails"
gem "importmap-rails"

gem "dotenv-rails"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  # Use sqlite3 as the database for Active Record
  gem "sqlite3", ">= 2.1"
end

group :test do
  gem "capybara"
  gem "cuprite"
  gem "database_cleaner-active_record"
end

group :production do
  gem "pg"
end
