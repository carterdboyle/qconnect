require "base64"
require "digest"
class VerificationService
  module B64u
    module_function
    def enc(b) = Base64.urlsafe_encode64(b, padding: false)
    def dec(s) = Base64.urlsafe_decode64(s)
  end

  # in: public_key, msg, signature (not b64)
    def self.verify(ps:, m:, sig:)  

    # Verify signature over M using PS
    ok = OQS::Dilithium2.verify(ps, m, sig)
    return { verified: false, error: "bad_signature" } unless ok
    ok
  rescue => e
    { verified: false, error: e.message }
  end
end