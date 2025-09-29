require "openssl"

module PQCryptoTest
  module_function

  def aes_gcm_encrypt(k_32, iv_12, plaintext)
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    cipher.key = k_32
    cipher.iv = iv_12
    cipher.auth_data = "".b
    c = cipher.update(plaintext) + cipher.final
    c + cipher.auth_tag
  end

  # Build valid encrypted message record
  # plaintext is a String
  def create_encrypted_message!(sender:, recipient:, plaintext:, t_ms:, conversation:)
    # 1) KEM encapsulate to recipient PK -> CK (ct) and K (ss)
    pk = recipient.user_key.pk
    ck, k = OQS::Kyber512.encaps(pk)

    # 2) Nonce: your model stores 16 bytes; AES-GCM users first 12 bytes
    nonce16 = SecureRandom.random_bytes(16)
    cm = aes_gcm_encrypt(k, nonce16[0, 12], plaintext.b)

    # 3) Sign T||n||CK||CM with sender's Dilithium secret key
    ss = sender.user_key_psk || sender.instance_variable_get(:@_dilitihium_ss)

    bytes = Proto.pack_msg(t_ms: t_ms, nonce: nonce16, ck: ck, cm: cm)
    sig = OQS::Dilithium2.sign(ss, bytes)

    Message.create!(
      sender_id: sender.id,
      recipient_id: recipient.id,
      conversation_id: conversation.id,
      t_ms: t_ms,
      nonce: nonce16,
      ck: ck,
      cm: cm,
      sig: sig
    )
  end

  def ensure_keys!(user)
    ps, ss = OQS::Dilithium2.keypair
    pk, sk = OQS::Kyber512.keypair
    UserKey.create!(user_id: user.id, ps: ps, pk: pk)
    user.instance_variable_set(:@_dilithium_ss, ss)
    user.instance_variable_set(:@_kyber_sk, sk)
    user
  end
end