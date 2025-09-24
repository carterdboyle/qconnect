class ContactsController < ApplicationController
  before_action :require_user!

  # GET /v1/contacts
  def index
    list = Contact.includes(contact_user: :user_key).where(user: current_user)
    render json: list.map { |c| 
      u = c.contact_user
      uk = u.user_key
      {
        handle: u.handle,
        user_id: u.id,
        ps_b64: Base64.urlsafe_encode64(uk&.ps),
        pk_b64: Base64.urlsafe_encode64(uk&.pk),
        alias: c.alias,
        added_at: c.created_at.iso8601
      }
    }
  end

  # GET /v1/contacts/:handle
  def show
    u = User.includes(:user_key).find_by!(handle: params[:handle])
    is_contact = Contact.exists?(user: current_user, contact_user: u)
    render json: {
      handle: u.handle, user_id: u.id, contact: is_contact,
      ps_b64: Base64.urlsafe_encode64(u.user_key&.ps), pk_b64: Base64.urlsafe_encode64(u.user_key&.pk)
    }
  rescue ActiveRecord::RecordNotFound
    render json: { message: "No such user" }, status: :not_found
  end

  private
  def require_user!
    render json: { message: "Not authenticated" }, status: :unauthorized unless current_user
  end
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end