class CsrfController < ApplicationController
  def show
    render json: { csrf: form_authenticity_token }
  end
end