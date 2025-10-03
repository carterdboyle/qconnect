require "test_helper"
require "capybara/cuprite"
require "database_cleaner/active_record"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    js_errors: true,
    browser_logger: $stdout,
    window_size: [1280, 900],
    headless: true,
    process_timeout: 30,
    browser_options: { 'disable-features': 'BlockInsecurePrivateNetworkRequests'})
end


Capybara.default_max_wait_time = 10

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite

  # Clean the test DB after each system test
  setup do
    DatabaseCleaner.strategy = :truncation, { except: %w[ar_internal_metadata schema_migrations]}
    DatabaseCleaner.start
  end

  teardown do
    DatabaseCleaner.clean
    if page.current_url&.start_with?("http")
      # Also reset browser storage do IndexedDB is fresh each test:
      page.execute_script("indexedDB.deleteDatabase('qconnect');")
      # (optional) clear cookies/localStorage as well
      page.execute_script("localStorage.clear(); sessionStorage.clear();")
    end
    reset_session!
  end
end