class LoginController < ApplicationController
  # POST /v1/login/challenge
  # in:  { handle }
  # out: { challenge_b64 }
  def challenge
    handle = params.require(:handle).to_s

    # Generate 256 random byes challenge
    challenge = SecureRandom.random_bytes(256);

    nonce = SecureRandom.hex(16);

    # Rewrite session to use Rails.cache
    key = "login:chal:#{nonce}"
    Rails.cache.write(
      key,
      { handle:, challenge_b64: Base64.urlsafe_encode64(challenge, padding: false) },
      expires_in: 2.minutes
    )

    render json: { challenge_b64: Base64.urlsafe_encode64(challenge, padding: false), nonce:}
  rescue
    render json: { message: "Handle required" }, status: :bad_request
  end

  # POST /v1/login/submit
  # in:  { signature_b64 }
  # out: { ok, user_id }
  def submit
    nonce = params.require(:nonce)

    key = "login:chal:#{nonce}"
    blob = Rails.cache.read(key)
    return render(json: { message: "No challenge" }, status: :bad_request) unless blob

    # Delete-on-read to prevent replay
    Rails.cache.delete(key)

    sig_b64 = params.require(:signature_b64)
    signature = Base64.urlsafe_decode64(sig_b64)
    challenge = Base64.urlsafe_decode64(blob[:challenge_b64])
    handle = blob[:handle]

    user = User.find_by(handle: handle)
    ps_b64 = Base64.urlsafe_encode64(user&.user_key&.ps)

    verified = 
      if ps_b64.present?
        ps = Base64.urlsafe_decode64(ps_b64)
        VerificationService.verify(ps:, m: challenge, sig: signature)
      else
        false
      end

    if verified
      session[:user_id] = user.id
      cookies.encrypted[:uid] = {
        value: user.id,
        same_site: :lax,
        secure: Rails.env.production?,
        domain: :all,
        httponly: true
      }
      render json: { ok: true, user_id: user.id }
    else
      sleep 0.15 #delay for enumeration attacks
      render json: { ok: false, message: "Invalid username or signature" }, status: :unauthorized
    end
  rescue ActionController::ParameterMissing
    render json: { message: "Signed challenge required"}, status: :bad_request
  rescue ArgumentError
    render json: { message: "Signed challenge must be base64" }, status: :bad_request
  end
end