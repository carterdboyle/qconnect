class ContactRequestsController < ApplicationController
  before_action :require_user!

  # POST /v1/contacts/requests
  # { handle, note? }
  def create
    recipient_handle = params.require(:handle).to_s
    note = params[:note].to_s

    recipient = User.find_by(handle: recipient_handle)

    cr = ContactRequest.create!(
      requester: current_user,
      recipient: recipient,
      recipient_handle: recipient_handle,
      note: note,
      status: :pending
    )

    render json: { id: cr.id, status: cr.status, recipient_handle: cr.recipient_handle }
  rescue ActionController::ParameterMissing => e
    render json: { message: "Missing param: #{e.param}"}, status: :bad_request
  end

  # GET /v1/contacts/requests
  # pending requests where I am the recipient
  def index
    mine = ContactRequest
      .where(status: :pending)
      .where("recipient_id = ? OR recipient_handle = ?", current_user.id, current_user.handle)
      .order(created_at: :asc)
    
    render json: mine.map { |r| 
      { id: r.id, from: r.requester.handle, note: r.note, at: r.created_at.iso8601 }
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

