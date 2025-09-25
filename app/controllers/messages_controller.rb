class MessagesController < ApplicationController
  before_action :require_user!

  T_THRESHOLD_S = 120

  # POST /v1/messages
  # { to_handle, t, n_b64, ck_b64, cm_b64, s_b64 }
  def create
    to_handle = params.require(:to_handle)
    t_ms = params.require(:t).to_i
    n_b64 = params.require(:n_b64)
    ck_b64 = params.require(:ck_b64)
    cm_b64 = params.require(:cm_b64)
    s_b64 = params.require(:s_b64)

    now_ms = (Time.current.to_f * 1000).to_i
    return render(json: { message: "stale" }, status: :unauthorized ) if (now_ms - t_ms ) > T_THRESHOLD_S * 1000;

    sender = current_user
    uk = sender.user_key or return render(json: { message: "no keys"}, status: :unprocessable_content )
    recip = User.find_by!(handle: to_handle)

    # Must be allowed to message - in address book
    allowed = Contact.exists?(user_id: sender.id, contact_user_id: recip.id)
    return render(json: { message: "not allowed"}, status: :forbidden ) unless allowed

    # Decode payload
    n = Base64.urlsafe_decode64(n_b64)
    ck = Base64.urlsafe_decode64(ck_b64)
    cm = Base64.urlsafe_decode64(cm_b64)
    s = Base64.urlsafe_decode64(s_b64)

    # Verify S over T||n||CK||CM with PS_sender
    msg_bytes = Proto.pack_msg(t_ms:, nonce: n, ck:, cm:)
    ok = VerificationService.verify(ps: uk.ps, m: msg_bytes, sig: s)
    return render(json: { message: "bad signature" }, status: :unauthorized) unless ok

    # Nonce uniqueness for (n, PS_sender)
    return render(json: { message: "replay"}, status: :unauthorized) unless NonceLedger.consume!(signer_ps: uk.ps, nonce: n)

    # Store and relay
    m = Message.create!(
      sender: sender, recipient: recip,
      t_ms:, nonce: n, ck:, cm:, sig: s
    )

    render json: { id: m.id, ok: true }
  rescue ActionController::ParameterMissing => e
    render json: { message: "missing #{e.param}" }, status: :bad_request
  rescue ActiveRecord::RecordNotFound
    render json: { message: "unknown recipient" }, status: :not_found
  rescue ArgumentError
    render json: { message: "invalid base64" }, status: :bad_request
  end

  # GET /v1/messages?box=inbox|outbox (default inbox)
  def index
    box = params[:box].to_s
    scope = 
      if box == "outbox"
        Message.where(sender_id: current_user.id).order(created_at: :asc)
      else
        Message.where(recipient_id: current_user.id).order(created_at: :asc)
      end
    
    render json: scope.map { |m| 
      {
        id: m.id,
        from: m.sender.handle,
        to: m.recipient.handle,
        t: m.t_ms,
        n_b64: Base64.urlsafe_encode64(m.nonce, padding: false)
        ck_b64: Base64.urlsafe_encode64(m.ck, padding: false)
        cm_b64: Base64.urlsafe_encode64(m.cm, padding: false)
        s_b64: Base64.urlsafe_encode64(m.sig, padding: false)
      }
    }
  end

  private
  def require_user!
    render json: { message: "Not authenticated" }, status: :unauthorized unless current_user
  end
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end