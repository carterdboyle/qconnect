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

    message = Message.new(
      sender: sender, recipient: recip,
      t_ms: t_ms, nonce: n, ck: ck, cm: cm, sig: s,
      conversation: Conversation.between(sender.id, recip.id)
    )
    
    # Verify S over T||n||CK||CM with PS_sender
    ok = VerificationService.verify(ps: uk.ps, m: message.bytes_for_signature, sig: s)
    return render(json: { message: "bad signature" }, status: :unauthorized) unless ok

    # Nonce uniqueness for (n, PS_sender)
    return render(json: { message: "replay"}, status: :unauthorized) unless NonceLedger.consume!(signer_ps: uk.ps, nonce: n)

    message.save!

    # Broadcast the json payload to the room
    payload = {
      id: message.id,
      from: sender.handle,
      to: recip.handle,
      t: message.t_ms,
      n_b64: Base64.urlsafe_encode64(message.nonce, padding: false),
      ck_b64: Base64.urlsafe_encode64(message.ck, padding: false),
      cm_b64: Base64.urlsafe_encode64(message.cm, padding: false),
      cm_b64: Base64.urlsafe_encode64(message.cm, padding: false),
      s_b64: Base64.urlsafe_encode64(message.sig, padding: false),
      conversation_id: message.conversation_id
    }
    ActionCable.server.broadcast("chat:#{message.conversation_id}", payload)

    render json: { id: message.id, ok: true }
  rescue ActionController::ParameterMissing => e
    render json: { message: "missing #{e.param}" }, status: :bad_request
  rescue ActiveRecord::RecordNotFound
    render json: { message: "unknown recipient" }, status: :not_found
  rescue ArgumentError
    render json: { message: "invalid base64" }, status: :bad_request
  end

  # NOT USED ANYMORE
  # GET /v1/messages?box=inbox|outbox (default inbox)
  def index
    box = params[:box].to_s
    scope = (box == 'outbox') ? Message.outbox_for(current_user) : Message.inbox_for(current_user)
    
    render json: scope.map(&:as_json_for_api)
  end

  private
  def require_user!
    render json: { message: "Not authenticated" }, status: :unauthorized unless current_user
  end
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end