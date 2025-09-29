class ContactRequestsController < ApplicationController
  before_action :require_user!

  T_THRESHOLD_S = 120

  # POST /v1/contacts/requests
  # { handle, t, n_b64, s_b64, ps_peer_b64, note? }
  def create
    recipient_handle = params.require(:handle).to_s
    t_ms = params.require(:t).to_i
    n_b64 = params.require(:n_b64)
    s_b64 = params.require(:s_b64)
    peer_b64 = params.require(:ps_peer_b64)
    note = params[:note].to_s

    now = (Time.current.to_f * 1000).to_i
    return render(json: { message: "stale" }, status: :unauthorized) if (now - t_ms) > T_THRESHOLD_S * 1000

    requester = current_user
    uk = requester.user_key or return render(json: { message: "no keys"}, status: :unprocessable_content )

    n = Base64.urlsafe_decode64(n_b64)
    sig = Base64.urlsafe_decode64(s_b64)
    ps_peer = Base64.urlsafe_decode64(peer_b64)

    # Verify S over (T || n || PS_peer ) using PS_requester
    msg = Proto.pack_contact_msg(t_ms:, nonce: n, peer_ps: ps_peer)
    ok = VerificationService.verify(ps: uk.ps, m: msg, sig: sig)
    return render(json: { message: "Bad signature"}, status: :unauthorized) unless ok

    # nonce freshness for (n, PS_requester)
    return render(json: { message: "Nonce is not fresh"}, status: :unauthorized) unless NonceLedger.consume!(signer_ps: uk.ps, nonce: n)
    
    recipient = User.find_by(handle: recipient_handle)

    cr = ContactRequest.create!(
      requester: requester,
      recipient: recipient,
      recipient_handle: recipient_handle,
      note: note,
      status: :pending,
      t_ms: t_ms,
      nonce: n,
      sig: sig,
      requester_ps: uk.ps
    )

    render json: { id: cr.id, status: cr.status, recipient_handle: cr.recipient_handle }
  rescue ActionController::ParameterMissing => e
    render json: { message: "Missing param: #{e.param}"}, status: :bad_request
  rescue ArgumentError => e
    render json: { message: "Invalid base64" }, status: :bad_request
  end

  # GET /v1/contacts/requests
  # pending requests where I am the recipient
  def index
    mine = ContactRequest
      .where(status: :pending)
      .where("recipient_id = ? OR recipient_handle = ?", current_user.id, current_user.handle)
      .order(created_at: :asc)
    
    render json: mine.map { |r| 
      { 
        id: r.id,
        from: r.requester.handle,
        note: r.note,
        t: r.t_ms,
        n_b64: Base64.urlsafe_encode64(r.nonce, padding: false),
        s_b64: Base64.urlsafe_encode64(r.sig, padding: false),
        from_ps_b64: Base64.urlsafe_encode64(r.requester_ps, padding: false),
        at: r.created_at.iso8601 
      }
    }
  end

  # POST /v1/contacts/requests/:id/respond
  # { decision: "accept" | "decline" }
  def respond
    cr = ContactRequest.find(params[:id])
    return render json: { message: "Not your request" }, status: :forbidden unless
      (cr.recipient_id == current_user.id) || (cr.recipient_handle == current_user.handle)

    decision = params.require(:decision)
    
    case decision
    when "accept"
      t_ms = params.require(:t).to_i
      n_b64 = params.require(:n_b64)
      s_b64 = params.require(:s_b64)

      now = (Time.current.to_f * 1000).to_i 
      return render(json: { message: "stale" }, status: :unauthorized) if (now - t_ms) > T_THRESHOLD_S * 1000

      n = Base64.urlsafe_decode64(n_b64)
      sig = Base64.urlsafe_decode64(s_b64)

      # Recipient must sign (T'||n'||PS_requester)
      uk_rec = current_user.user_key or return render(json: { message: "no keys"}, status: :unprocessable_content )
      msg = Proto.pack_contact_msg(t_ms:, nonce: n, peer_ps: cr.requester_ps)
      ok = VerificationService.verify(ps: uk_rec.ps, m: msg, sig: sig)
      return render(json: { message: "bad signature"}, status: :unauthorized) unless ok

      # Nonce freshness for (n, PS_recipient)
      return render(json: { message: "replay"}, status: :unauthorized) unless NonceLedger.consume!(signer_ps: uk_rec.ps, nonce: n)
      
      cr.update!(status: :accepted, recipient: current_user)
      # create reciprocal contacts
      Contact.find_or_create_by!(user: current_user, contact_user: cr.requester)
      Contact.find_or_create_by!(user: cr.requester, contact_user: current_user)

      render json: { ok: true, status: cr.status }
    when "decline"
      cr.update!(status: :declined, recipient: current_user)
      render json: { ok: true, status: cr.status }
    else
      render json: { message: "Invalid decision" }, status: :bad_request
    end
  rescue ActiveRecord::RecordNotFound
    render json: { message: "Unknown request" }, status: :not_found
  rescue ActiveController::ParameterMissing => e
    render json: { message: "Missing param: #{e.param}"}, status: :bad_request
  end

  private
  def require_user!
    render json: { message: "Not authenticated" }, status: :unauthorized unless current_user
  end
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
  
end

