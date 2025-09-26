class SessionsController < ApplicationController
  def show
    if current_user
      render json: { user_id: current_user.id, handle: current_user.handle }
    else
      render json: { user_id: nil, handle: nil }
    end
  end

  def destroy 
    reset_session
    cookies.delete(:uid, same_site: :lax, domain: :all, secure: Rails.env.production?)
    head :no_content
  end

  private
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end