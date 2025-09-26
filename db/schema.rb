# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_26_221900) do
  create_table "chat_reads", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.integer "user_id", null: false
    t.bigint "last_read_message_id"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "last_read_t_ms", default: 0, null: false
    t.index ["conversation_id", "user_id"], name: "index_chat_reads_on_conversation_id_and_user_id", unique: true
    t.index ["conversation_id"], name: "index_chat_reads_on_conversation_id"
    t.index ["user_id"], name: "index_chat_reads_on_user_id"
  end

  create_table "contact_requests", force: :cascade do |t|
    t.integer "requester_id", null: false
    t.integer "recipient_id"
    t.string "recipient_handle", null: false
    t.text "note"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "t_ms", null: false
    t.binary "nonce", null: false
    t.binary "sig", null: false
    t.binary "requester_ps", null: false
    t.index ["recipient_handle", "status"], name: "index_contact_requests_on_recipient_handle_and_status"
    t.index ["recipient_handle"], name: "index_contact_requests_on_recipient_handle"
    t.index ["recipient_id", "status"], name: "index_contact_requests_on_recipient_id_and_status"
    t.index ["recipient_id"], name: "index_contact_requests_on_recipient_id"
    t.index ["requester_id", "status"], name: "index_contact_requests_on_requester_id_and_status"
    t.index ["requester_id"], name: "index_contact_requests_on_requester_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "contact_user_id", null: false
    t.string "alias"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_user_id"], name: "index_contacts_on_contact_user_id"
    t.index ["user_id", "contact_user_id"], name: "index_contacts_on_user_id_and_contact_user_id", unique: true
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "key", null: false
    t.integer "a_id", null: false
    t.integer "b_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["a_id"], name: "index_conversations_on_a_id"
    t.index ["b_id"], name: "index_conversations_on_b_id"
    t.index ["key"], name: "index_conversations_on_key", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "sender_id", null: false
    t.integer "recipient_id", null: false
    t.bigint "t_ms", null: false
    t.binary "nonce", null: false
    t.binary "ck", null: false
    t.binary "cm", null: false
    t.binary "sig", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "conversation_id", null: false
    t.index ["conversation_id", "t_ms", "id"], name: "index_messages_on_conversation_id_and_t_ms_and_id"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["recipient_id"], name: "index_messages_on_recipient_id"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "used_nonces", force: :cascade do |t|
    t.binary "signer_ps", null: false
    t.binary "nonce", null: false
    t.datetime "seen_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["signer_ps", "nonce"], name: "index_used_nonces_on_signer_ps_and_nonce", unique: true
  end

  create_table "user_keys", primary_key: "user_id", force: :cascade do |t|
    t.binary "ps", null: false
    t.binary "pk", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "handle", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["handle"], name: "index_users_on_handle", unique: true
  end

  add_foreign_key "chat_reads", "conversations"
  add_foreign_key "chat_reads", "users"
  add_foreign_key "contact_requests", "users", column: "recipient_id"
  add_foreign_key "contact_requests", "users", column: "requester_id"
  add_foreign_key "contacts", "users"
  add_foreign_key "contacts", "users", column: "contact_user_id"
  add_foreign_key "messages", "users", column: "recipient_id"
  add_foreign_key "messages", "users", column: "sender_id"
end
