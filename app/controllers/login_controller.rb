class LoginController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /v1/login/challenge
  # in:  { handle }
  # out: { challenge_b64 }
  def challenge
    handle = params.require(:handle).to_s

    # Generate 256 random byes challenge
    challenge.SecureRandom.random_bytes(256);

    # Store in session for submit step (b64url to be sage in cookie)
    session[:login_handle] = handle
    session[:login_challenge] = Base64.urlsafe_encode64(challenge, padding: false)

    render json: { challenge_b64: Base64.urlsafe_encode64(challenge, padding: false)}
  rescue
    render json: { message: "Handle required" }, status: :bad_request
  end

    # POST /v1/login/submit
  # in:  { signature_b64 }
  # out: { ok, user_id }
  def challenge
    handle = session[:login_handle]
    session.delete(:login_handle)
    challenge_b64 = session[:login_challenge]
    session.delete(:login_challenge)
    return render json: { message: "No challenge" }, status: :bad_request if handle.blank? || challenge_b64.blank?

    sig_b64 = params.require(:signature_b64)
    signature = Base64.urlsafe_decode64(sig_b64)
    challenge = Base64.urlsage_decode64(challenge_b64)

    user = User.find_by(handle: handle)
    ps_b64 = Base64.urlsafe_encode64(user&.user_key&.ps)

    verified = 
      if ps_b64.present?
        ps = Base64.urlsafe_decode64(ps_b64)
        VerificationService.verify(ps:, m: challenge, sig: signature)

    if verified
      session[:user_id] = user.id
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