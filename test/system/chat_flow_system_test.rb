require "application_system_test_case"

class ChatFlowSystemTest < ApplicationSystemTestCase

  test "two users register, add, chat across days, and banners/dividers render correctly" do
    # visit the terminal in two sessions (alice / bob)
    using_session(:alice) do
      visit "/"
      snap_step!("alice_home")
      wait_for_terminal_line("QCONNECT SECURE CONSOLE", snap: "alice_console_ready")

      term_exec "handle alice"
      wait_for_terminal_line("- Handle set: alice", snap: "alice_handle")

      term_exec "genkeys"
      wait_for_terminal_line("- Generated ML-DSA-44 + ML-KEM-512 keys", snap: "alice_genkeys")

      term_exec "register"
      wait_for_terminal_line("- Registered ✔", snap: "alice_register")

      term_exec "login"
      wait_for_terminal_line("- Logged in sucessfully ✔", snap: "alice_login")
    end

    using_session(:bob) do
      visit "/"
      snap_step!("bob_home")
      expect_line("QCONNECT SECURE CONSOLE")

      term_exec "handle bob"
      wait_for_terminal_line("- Handle set: bob", snap: "bob_handle")
      term_exec "genkeys"; wait_for_terminal_line("- Generated ML-DSA-44 + ML-KEM-512 keys", snap: "bob_genkeys")
      term_exec "register"; wait_for_terminal_line("- Registered ✔", snap: "bob_register")
      term_exec "login"; wait_for_terminal_line("- Logged in sucessfully ✔", snap: "bob_login")      
    end

    # alice sends a contact request to Bob, and he accepts
    using_session(:alice) do
      term_exec "request bob Hey bob!"
      wait_for_terminal_line("- Request sent to bob!", snap: "alice_request_bob")
    end

    using_session(:bob) do
      term_exec "requests"
      wait_for_terminal_line("id:")
      # grab ID from the last requests line
      req_id = page.all("#terminal .line").map(&:text).grep(/id:\s+(\d+)/).last[/\d+/]
      term_exec "accept #{req_id}"
      wait_for_terminal_line("added as a contact", snap: "bob_accept")
    end

    # Simulate a conversation that started a few days ago from alice -> bob
    days_ago = 3
    t_past_ms = ((Time.current - days_ago.days).to_i * 1000)

    using_session(:alice) do
      # Make "Chatting with @bob" and send two messages from the past day
      travel_browser_to(t_past_ms)
      term_exec "chat bob"
      wait_for_terminal_line("Chatting with @bob!", snap: "alice_chat_open")
      term_exec "Hello from three days ago!"
      wait_for_terminal_line("Hello from three days", snap: "alice_past_msg1")
      # res = page.evaluate_async_script(<<~JS, "bob", "Hello from three days ago!")
      #   (to, txt, done) => {
      #     window.sendMessageAndGetId(to, txt)
      #       .then(id => done(id))
      #       .catch(e => done("ERR: " + e.message));
      #   }
      # JS
      # puts "sendMessageAndGetId => #{res.inspect}"
      term_exec "And another from the same day"
      wait_for_terminal_line("And another from the same", snap: "alice_past_msg2")
      # Exit chat
      term_exec "/q", snap: "alice_chat_quit"
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

        snap_step!("bob_after_unread_render")
        # Leave chat without responding
        term_exec "/q", snap: "bob_chat_quit"
      rescue
        dump_terminal
        raise
      end
    end

    # Afterwards Alice sends one new message TODAY
    using_session(:alice) do
      term_exec "chat bob"
      wait_for_terminal_line("Chatting with @bob!", snap: "alice_chat_open_today")
      term_exec "A fresh message today"
      wait_for_terminal_line("A fresh message", snap: "alice_today_msg")
      term_exec "/q", snap: "alice_chat_quit_today"
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
        snap_step!("bob_after_asserts_2nd_open")
      rescue
        dump_terminal
        raise
      end
    end
  end
end