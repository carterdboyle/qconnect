module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_current_user
    end

    private

    def find_current_user
      uid = cookies.encrypted[:uid]
      User.find_by(id: uid)
    end
  end
end