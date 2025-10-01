# frozen_string_literal: true
require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  # base64url helpers (no padding)
  def b64u(bytes) = Base64.urlsafe_encode64(bytes, padding: false)
  def unb64(str) = Base64.urlsafe_decode64(str)

  test "successful registration stores keys and verifies challenge" do
    handle = "testuser_#{SecureRandom.hex(4)}"

    # -- client keygen (real ML-DSA-44 + ML-KEM-512)
    ps, ss = OQS::Dilithium2.keypair
    pk, sk = OQS::Kyber512.keypair

    # -- 1) init: send handle + public keys, get (m, ct) back ---
    post "/v1/register/init",
      params: { handle:, ps_b64: b64u(ps), pk_b64: b64u(pk) }, as: :json

    assert_response :success
    body = JSON.parse(@response.body)
    assert body["m_b64"].present?, "server must return signing challenge m_b64"
    assert body["ct_b64"].present?, "server must return kyber ciphertext ct_b64"
    assert body["nonce"].present?, "server must return a nonce"

    m = unb64(body["m_b64"])
    ct = unb64(body["ct_b64"])
    nonce = body["nonce"]

    # -- 2) client signs and decapsulates
    sig = OQS::Dilithium2.sign(ss, m)
    kp = OQS::Kyber512.decaps(sk, ct)
    kp16 = kp.byteslice(0, 16)

    # -- 3) verify: send signature + K'
    post "/v1/register/verify",
      params: { handle:, sig_b64: b64u(sig), kp_b64: b64u(kp16), nonce: }, as: :json

    assert_response :success
    res = JSON.parse(@response.body)
    assert res["verified"], "registration should verify"

    # --- DB assertions
    user = User.find_by(handle:)
    assert user, "user should be created"
    uk = user.user_key
    assert uk, "user_key should be created"
    assert_equal ps, uk.ps, "stored Dilithium2 public key must match"
    assert_equal pk, uk.pk, "store Kyber public key must match"
  end

  test "registration fails with bad signature" do
    handle = "bad_sig_#{SecureRandom.hex(4)}"
    ps, ss = OQS::Dilithium2.keypair
    pk, sk = OQS::Kyber512.keypair

    post "/v1/register/init",
      params: { handle:, ps_b64: b64u(ps), pk_b64: b64u(pk) }, as: :json
    
    assert_response :success
    body = JSON.parse(@response.body)
    m = unb64(body["m_b64"])
    ct = unb64(body["ct_b64"])
    nonce = body["nonce"]

    # Wrong signature (sign different message)
    sig_wrong = OQS::Dilithium2.sign(ss, "not the right message".b)
    kp16 = OQS::Kyber512.decaps(sk, unb64(body["ct_b64"])).byteslice(0,16)

    post "/v1/register/verify",
      params: { handle:, sig_b64: b64u(sig_wrong), kp_b64: b64u(kp16), nonce: }, as: :json

    assert_response :unauthorized
    refute User.exists?(handle:), "user should not be created on bad signature"
  end

  test "registration rejects duplicate handle" do
    handle = "dupe_#{SecureRandom.hex(4)}"
    # First registration
    ps1, ss1 = OQS::Dilithium2.keypair
    pk1, sk1 = OQS::Kyber512.keypair

    post "/v1/register/init",
      params: { handle: handle, ps_b64: b64u(ps1), pk_b64: b64u(pk1) },
      as: :json
    body = JSON.parse(@response.body)
    sig1 = OQS::Dilithium2.sign(ss1, unb64(body["m_b64"]))
    kp16 = OQS::Kyber512.decaps(sk1, unb64(body["ct_b64"])).byteslice(0, 16)
    nonce = body["nonce"]
    post "/v1/register/verify",
      params: { handle: handle, sig_b64: b64u(sig1), kp_b64: b64u(kp16), nonce: },
      as: :json
    assert_response :success

    # Second attempt with same handle should fail
    ps2, _ss2 = OQS::Dilithium2.keypair
    pk2, _sk2 = OQS::Kyber512.keypair
    post "/v1/register/init",
      params: { handle: handle, ps_b64: b64u(ps2), pk_b64: b64u(pk2), nonce: },
      as: :json
    body2 = JSON.parse(@response.body)
    sig2 = OQS::Dilithium2.sign(_ss2, unb64(body["m_b64"]))
    kp16_2 = OQS::Kyber512.decaps(_sk2, unb64(body["ct_b64"])).byteslice(0, 16)
    nonce2 = body["nonce"]
    post "/v1/register/verify",
      params: { handle: handle, sig_b64: b64u(sig2), kp_b64: b64u(kp16_2), nonce: },
      as: :json

    assert_includes [409, 422, 400, 401], @response.status,
      "duplicate handle should be rejected"
  end
end