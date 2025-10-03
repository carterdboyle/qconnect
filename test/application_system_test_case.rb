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

  def snap_step!(label, selector: ".frame", full: false)
    sess = (Capybara.session_name || :default).to_s
    @__steps__ ||= Hash.new(0)
    @__steps__[sess] += 1
    step = format("%02d", @__steps__[sess])

    dir = Rails.root.join("tmp/screenshots", sess)
    FileUtils.mkdir_p(dir)
    path = dir.join("#{step}-#{label.gsub(/\s+/,'_')}.png")

    # make sure terminal exists and has something in it before shooting
    page.assert_selector(selector, wait: 10)

    # ensure black background even if page is transparent
    page.execute_script <<~JS
      document.documentElement.style.background = '#000';
      document.body.style.background = '#000';
    JS

    # Crop to terminal
    page.driver.save_screenshot(path.to_s, full: full, selector: selector)
    puts "[SHOT] #{path}"
    path
  end

    # Helpers to drive terminal
  def dump_terminal
    terminal_lines = page.all("#terminal .line", minimum: 0).map(&:text)
    puts "\n=== TERMINAL DUMP ===\n#{terminal_lines.join("\n")}\n=== /TERMINAL DUMP ===\n"
    path = Rails.root.join("tmp/screenshots/terminal-#{Time.now.to_i}.png")
    page.save_screenshot(path.to_s, full: true)
    puts "[Screenshot Image]: #{path}"
  end
  
  def after_teardown
    dump_terminal unless passed?
    super
  end

  def wait_until_local_messages(owner, peer, at_least:, timeout: 15)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    last = -1
    loop do
      count = page.evaluate_async_script(<<~JS, owner, peer)
        const [owner, peer] = arguments; const done = arguments[2];
        const req = indexedDB.open("qconnect", 5);
        req.onerror = () => done(-1);
        req.onsuccess = () => {
          const db  = req.result;
          const tx  = db.transaction("messages", "readonly");
          const os  = tx.objectStore("messages");
          const idx = os.index("by_owner_peer_time_id");
          const range = IDBKeyRange.bound([owner, peer, -Infinity, -Infinity],[owner, peer, Infinity, Infinity]);
          let n = 0;
          idx.openKeyCursor(range).onsuccess = e => { const c = e.target.result; if (c) { n++; c.continue(); } };
          tx.oncomplete = () => done(n);
        };
      JS
      # puts "DEBUG IDB #{owner}⇄#{peer} count=#{count}" if count != last
      last = count
      break if count >= at_least
      raise "IDB denied" if count == -1
      raise "timeout waiting IDB=#{at_least}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
  end

  def wait_for_text_in_terminal(regex, timeout: 15)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      txt = page.evaluate_script("document.querySelector('#terminal')?.innerText || ''")
      return true if txt&.match?(regex)
      raise "timeout waiting for #{regex.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
  end

  def term_exec(cmd, snap: nil)
    # ensure the input exists and has focus
    page.assert_selector "input", wait: 10

    # set value and dispatch Enter, which the REPL listens for
    page.execute_script(<<~JS, cmd)
      (function(val){
        const el = document.querySelector('#input')
        el.value = val;
        const e = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true });
        el.dispatchEvent(e);
      })(arguments[0]);
    JS
    snap_step!(snap) if snap
  end

  def wait_for_terminal_line(text, timeout: 15, snap: nil)
    page.assert_selector "#terminal .line", text: text, wait: timeout
    snap_step!(snap) if snap
  end
  
  def expect_line(text)
    page.assert_selector("#terminal .line", text: text)
  end

  def lines
    page.all("#terminal .line").map(&:text)
  end

  def travel_browser_to(t_ms)
    ts = t_ms.to_i
    page.execute_script <<~JS, ts
      (function(ts){
        // Stash originals once
        if (!window.__timeFreeze) {
          window.__timeFreeze = {
            RealDate: window.Date,
            realNow: (window.performance && typeof performance.now === 'function')
                    ? performance.now.bind(performance) : null
          };
        }
        const RealDate = window.__timeFreeze.RealDate;

        // Proper Date subclass that works with `new Date()` and `Date.now()`
        class MockDate extends RealDate {
          constructor(...args){ return args.length ? new RealDate(...args) : new RealDate(ts); }
          static now(){ return ts; }
        }
        Object.setPrototypeOf(MockDate, RealDate);               // static members
        Object.setPrototypeOf(MockDate.prototype, RealDate.prototype);

        // Swap globals
        window.Date = MockDate;

        // Also pin performance.now so elapsed math stays consistent
        if (window.__timeFreeze.realNow) {
          const base = window.__timeFreeze.realNow();
          const offset = ts - base;
          performance.now = function(){ return window.__timeFreeze.realNow() + offset - base; };
        }
      })(arguments[0]);
    JS
  end

  def restore_browser_clock
    page.execute_script <<~JS
      (function(){
        const TF = window.__timeFreeze;
        if (!TF) return;                 // nothing to restore
        window.Date = TF.RealDate;
        if (TF.realNow) performance.now = TF.realNow;
        delete window.__timeFreeze;
      })();
    JS
  end

  def travel_both_to(t_ms)
    page.execute_script("window.__TEST_FAKE_NOW_MS = #{t_ms.to_i}")
    travel_browser_to(t_ms)
  end

  def back_to_real_time
    page.execute_script("delete window.__TEST_FAKE_NOW_MS")
    restore_browser_clock
  end

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