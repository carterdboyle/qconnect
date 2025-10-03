require "application_system_test_case"

class ChatFlowSystemTest < ApplicationSystemTestCase

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
      puts "DEBUG IDB #{owner}⇄#{peer} count=#{count}" if count != last
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

  def term_exec(cmd)
    # ensure the input exists and has focus
    assert_selector "input", wait: 10
    input = find "#input"

    # set value and dispatch Enter, which the REPL listens for
    page.execute_script(<<~JS, cmd)
      (function(val){
        const el = document.querySelector('#input')
        el.value = val;
        const e = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true });
        el.dispatchEvent(e);
      })(arguments[0]);
    JS
  end

  def wait_for_terminal_line(text, timeout: 15)
    assert_selector "#terminal .line", text: text, wait: timeout
  end
  
  def expect_line(text)
    assert_selector("#terminal .line", text: text)
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

  test "two users register, add, chat across days, and banners/dividers render correctly" do
    # visit the terminal in two sessions (alice / bob)
    using_session(:alice) do
      visit "/"
      expect_line("QCONNECT SECURE CONSOLE")
      term_exec "handle alice"
      wait_for_terminal_line("- Handle set: alice")
      term_exec "genkeys"; wait_for_terminal_line("- Generated ML-DSA-44 + ML-KEM-512 keys")
      term_exec "register"; wait_for_terminal_line("- Registered ✔")
      term_exec "login"; wait_for_terminal_line("- Logged in sucessfully ✔")
    end

    using_session(:bob) do
      visit "/"
      expect_line("QCONNECT SECURE CONSOLE")
      term_exec "handle bob"
      wait_for_terminal_line("- Handle set: bob")
      term_exec "genkeys"; wait_for_terminal_line("- Generated ML-DSA-44 + ML-KEM-512 keys")
      term_exec "register"; wait_for_terminal_line("- Registered ✔")
      term_exec "login"; wait_for_terminal_line("- Logged in sucessfully ✔")      
    end

    # alice sends a contact request to Bob, and he accepts
    using_session(:alice) do
      term_exec "request bob Hey bob!"
      wait_for_terminal_line("- Request sent to bob!")
    end

    using_session(:bob) do
      term_exec "requests"
      wait_for_terminal_line("id:")
      # grab ID from the last requests line
      req_id = page.all("#terminal .line").map(&:text).grep(/id:\s+(\d+)/).last[/\d+/]
      term_exec "accept #{req_id}"
      wait_for_terminal_line("added as a contact")
    end

    # Simulate a conversation that started a few days ago from alice -> bob
    days_ago = 3
    t_past_ms = ((Time.current - days_ago.days).to_i * 1000)

    using_session(:alice) do
      # Make "Chatting with @bob" and send two messages from the past day
      travel_browser_to(t_past_ms)
      term_exec "chat bob"
      wait_for_terminal_line("Chatting with @bob!")
      term_exec "Hello from three days ago!"
      # res = page.evaluate_async_script(<<~JS, "bob", "Hello from three days ago!")
      #   (to, txt, done) => {
      #     window.sendMessageAndGetId(to, txt)
      #       .then(id => done(id))
      #       .catch(e => done("ERR: " + e.message));
      #   }
      # JS
      # puts "sendMessageAndGetId => #{res.inspect}"
      term_exec "And another from the same day"
      # Exit chat
      term_exec "/q"
      back_to_real_time
    end

    # bob opens up the chat but does not respond
    using_session(:bob) do
      begin
        term_exec "chat alice"
        wait_for_terminal_line("Chatting with @alice!")

        # Wait for 2 messages to be pulled+decrypted+stored locally
        wait_until_local_messages("bob", "alice", at_least: 2, timeout: 20)

        # Now wait for the banner and divider to appear in terminal
        wait_for_text_in_terminal(/2 new messages!/, timeout: 20)
        wait_for_text_in_terminal(/^——/, timeout: 20)

        # He should see the unread banner and the day divider for the past day
        # The exact wording comes from your rendering logic
        # "2 new messages!" line should appear
        # assert_selector "#terminal .line", text: /2 new messages!/, wait: 15
        # assert_selector "#terminal .line", text: /^——/, wait: 15

        # Leave chat without responding
        term_exec "/q"
      rescue
        dump_terminal
        raise
      end
    end

    # Afterwards Alice sends one new message TODAY
    using_session(:alice) do
      term_exec "chat bob"
      wait_for_terminal_line("Chatting with @bob!")
      term_exec "A fresh message today"
      term_exec "/q"
    end

    # Bob opens the chat again; expects banner for 1 new, then today's divider, then message
    using_session(:bob) do
      begin
        term_exec "chat alice"
        wait_for_terminal_line("Chatting with @alice!")

        # assert_selector("#terminal .line", text: /1 new message!/, wait: 15)
        # assert_selector("#terminal .line", text: /^——/, wait: 15)
        # assert_selector("#terminal .line", text: "A fresh message today", wait: 15)

        # Ensure at least 1 local message (the one Alice just sent)
        wait_until_local_messages("bob", "alice", at_least: 3, timeout: 20) # 2 old + 1 new

        wait_for_text_in_terminal(/1 new message!/,        timeout: 20)
        wait_for_text_in_terminal(/^——/,                   timeout: 20)
        wait_for_text_in_terminal(/A fresh message today/, timeout: 20)
        
        # check order on screen
        all_lines = lines
        one_new_idx = all_lines.index { |l| l =~ /1 new message/}
        today_div_idx = all_lines.rindex { |l| l =~ /^——/ } #today's divider appears
        msg_idx = all_lines.index { |l| l.include?("A fresh message today") }

        assert one_new_idx, "expected '1 new message!' banner"
        assert today_div_idx, "expected a divider for today"
        assert msg_idx, "expected the new message text to be printed"

        assert one_new_idx < today_div_idx, "banner should print before today's divider"
        assert today_div_idx < msg_idx, "divider should appear before the message"
      rescue
        dump_terminal
        raise
      end
    end
  end
end