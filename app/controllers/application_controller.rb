class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  protect_from_forgery with: :exception
  allow_browser versions: :modern

  private

  # Milliseconds since epoch, test-only overrideable via header
  def now_ms
    if Rails.env.test?
      hdr = request.headers['X-Fake-Now-Ms']
      return Integer(hdr) rescue nil if hdr.present?
    end
    (Time.now.to_f * 1000).to_i
  end
end
