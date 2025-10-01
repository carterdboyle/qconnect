class RegisterController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /v1/register/init
  # in: { handle, ps (b64url), pk (b64url)}
  # out: { user_id, m (b64url 16B), c (b64url Kyber CT) }
  def init
    handle = params.require(:handle)
    ps_b64 = params.require(:ps_b64)
    pk_b64 = params.require(:pk_b64)

    # debug = ActiveModel::Type::Boolean.new.cast(params[:debug])
    render json: RegistrationService.init(handle:, ps_b64:, pk_b64:)
  rescue  => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def verify
    handle = params.require(:handle)
    sig_b64 = params.require(:sig_b64)
    kp_b64 = params.require(:kp_b64)
    nonce = params.require(:nonce)
    
    res = RegistrationService.verify(handle:, sig_b64:, kp_b64:, nonce:)
    if !res[:verified]
      render json: { ok: false, error: res[:error] }, status: :unauthorized
    else
      render json: res
    end
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_content
  end
end