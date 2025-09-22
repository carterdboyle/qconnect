class RegisterController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token

  # POST /v1/register/init
  # in: { handle, ps (b64url), pk (b64url)}
  # out: { user_id, m (b64url 16B), c (b64url Kyber CT) }
  def init
    handle = params.require(:handle)
    ps_b = Base64.urlsafe_decode64(params.require(:ps))
    pk_b = Base64.urlsafe_decode64(params.require(:pk))

    user = User.create!(handle:)
    UserKey.create!(user_id: user.id, ps: ps_b, pk: pk_b)

    m = SecureRandom.random_bytes(16)

    # Mock up stuff here until ffi ruby
    k = SecureRandom.random_bytes(32)
    c = k.bytes.map { |b| (b ^ 0xAA) }.pack("C*")

    Rails.cache.write("reg:#{user.id}", { m:, k: }, expires_in: 5.minutes )

    render json: {
      user_id: user.id,
      m: Base64.urlsafe_encode64(m),
      c: Base64.urlsafe_encode64(c)
    }
  rescue  => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def verify
    user_id = params.require(:user_id)
    s_b = Base64.urlsafe_decode64(params.require(:s))
    k_prime = Base64.urlsafe_decode64(params.require(:k_prime))

    cache = Rails.cache.read("reg:#{user_id}") || (raise "challenge missing/expired")
    m = cache[:m]
    k = cache[:k]

    user = User.find(user_id)
    ps_b = user.user_key.ps

    # TODO: No ffi libopqs yet for verifying signature yet
    # So just check for the presence of the signature and that K'
    # matches K
    raise "missing_sig" if s_b.nil? || s_b.empty?

    unless ActiveSupport::SecurityUtils.secure_compare(k, k_prime)
      raise "kem_mismatch"
    end

    Rails.cache.delete("reg:#{user_id}")

    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_content
  end
end