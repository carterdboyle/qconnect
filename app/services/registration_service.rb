require "base64"
require "digest"
class RegistrationService
  module B64u
    module_function
    def enc(b) = Base64.urlsafe_encode64(b, padding: false)
    def dec(s) = Base64.urlsafe_decode64(s)
  end

  # Step 1: server creates M and C, caches {m, k} for later compare
  # in: ps_b64u, pk_b64u
  # out: { m, ct } (both b64url)
  def self.init(handle:, ps_b64:, pk_b64:)
    ps = B64u.dec(ps_b64);
    pk = B64u.dec(pk_b64);

    ct, k = OQS::Kyber512.encaps_and_k(pk);

    # Signing challenge
    m = SecureRandom.random_bytes(256)

    # Short-lived nonce to bind to this init
    nonce = SecureRandom.hex(16)

    Rails.cache.write("reg:#{handle}:#{nonce}", { ps:, pk:, m:, k: }, expires_in: 2.minutes)

    { m_b64: B64u.enc(m), ct_b64: B64u.enc(ct), nonce:}
  end

  # Step 2: client posts back K' and signature S over M (with PS)
  # in: handle, sig_b64u, k_prime_b64u
  def self.verify(handle:, sig_b64:, kp_b64:, nonce:)
    state = Rails.cache.read("reg:#{handle}:#{nonce}")
    return { verified: false, error: "expired" } unless state

    ps, pk, m, k = state.values_at(:ps, :pk, :m, :k)
    # Check K == K'
    k_prime = B64u.dec(kp_b64)

    return { verified: false, error: "kem_mismatch" } unless k_prime.bytesize == 16 && k_prime == k

    # Verify signature over M using PS
    sig = B64u.dec(sig_b64)
    ok = OQS::Dilithium2.verify(ps, m, sig)
    return { verified: false, error: "bad_signature" } unless ok

    ActiveRecord::Base.transaction do
      user = User.create!(handle:)
      UserKey.create!(user_id: user.id, ps: ps, pk: pk)
    end

    Rails.cache.delete("reg:#{handle}:#{nonce}")
    { verified: true }
  rescue ActiveRecord::RecordNotUnique
    { verified: false, error: "handle_taken" }
  rescue => e
    { verified: false, error: e.message }
  end
end