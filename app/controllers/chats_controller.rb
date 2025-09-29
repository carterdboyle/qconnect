class ChatsController < ApplicationController
  before_action :require_user!

  # POST /v1/chats/open { handle }
  def open
    peer = User.find_by!(handle: params.require(:handle))
    
    # make sure user is a contact
    unless Contact.exists?(user_id: current_user.id, contact_user_id: peer.id)
      return render json: { message: "not allowed (not in contacts)"}, status: :forbidden
    end
    
    # ensure a read row exists for me
    convo = Conversation.between(current_user.id, peer.id)
    ChatRead.find_or_create_by!(conversation: convo, user: current_user)

    # last 50 messages in the convo
    msgs = convo.messages.order(created_at: :asc).last(50)
    render json: {
      conversation_id: convo.id,
      peer: peer.handle,
      history: msgs.map(&:as_json_for_api)
    }
  rescue ActiveRecord::RecordNotFound
    render json: { message: "no such user" }, status: :not_found
  end

  # GET /v1/chats/:id/messages?after_t=1231232342829034&after_id=123&limit=200
  # Returns encrypted messages for this conversation with id > after_id
  def messages_since
    convo = Conversation.find(params[:id])

    # authorize: user must be participant
    unless [convo.a_id, convo.b_id].include?(current_user.id)
      return render json: { message: "forbidden" }, status: :forbidden
    end

    after_t = params[:after_t].to_i
    after_id = params[:after_id].to_i
    limit = (params[:limit] || 200).to_i.clamp(1, 1000)

    msgs = convo.messages
      .where("t_ms > ? OR (t_ms = ? AND id > ?)", after_t, after_t, after_id)
      .order(Arel.sql("t_ms ASC, id ASC"))
      .limit(limit)

    render json: msgs.map(&:as_json_for_api)
  rescue ActiveRecord::RecordNotFound
    render json: { message: "not found" }, status: :not_found
  end

  # GET /v1/chats/:id/last_read
  def last_read
    convo = Conversation.find(params[:id])
    
    unless [convo.a_id, convo.b_id].include?(current_user.id)
      return render json: { message: "forbidden" }, status: :forbidden
    end
    cr = ChatRead.find_by(conversation_id: convo.id, user_id: current_user.id)
    tms = cr&.last_read_message_id ? Message.where(id: cr.last_read_message_id).pick(:t_ms) : 0
    
    render json: { 
      last_read_message_id: cr&.last_read_message_id || 0,
      last_read_t_ms: tms || 0,
    }
  rescue ActiveRecord::RecordNotFound
    render json: { message: "No such user or conversation" }, status: :not_found
  end

  # GET /v1/chats/summary
  # returns unread counts per peer and last_t for sorting
  def summary
    # conversations where I am a or b
    convos = Conversation.where("a_id = ? OR b_id = ?", current_user.id, current_user.id)
    result = []
    convos.includes(:messages).find_each do | c |
      peer_id = c.peer_for(current_user.id)
      last = c.messages.order(Arel.sql("t_ms DESC, id DESC")).first
      next unless last

      # unread: messages in convo to me with id > read marker
      read = ChatRead.find_by(conversation_id: c.id, user_id: current_user.id)
      last_read_id = read&.last_read_message_id || 0
      last_read_t = last_read_id ? Message.where(id: last_read_id).pick(:t_ms) : 0

      unread = c.messages.where(recipient_id: current_user.id)
                        .where("(t_ms, id) > (?, ?)", last_read_t || 0, last_read_id || 0)
                        .count

      peer = User.find_by(id: peer_id)
      result << { handle: peer&.handle, unread:, last_t: last.t_ms, conversation_id: c.id}
    end
    render json: result.sort_by { |h| -h[:last_t].to_i}
  end

  # POST /v1/chats/:id/read
  def read
    convo = Conversation.find(params[:id])
    # last message addressed to me in this conversation
    last_to_me = convo.messages.where(recipient_id: current_user.id).order(Arel.sql("t_ms DESC, id DESC")).first
    # cr = ChatRead.find_or_create_by!(conversation: convo, user: current_user)
    if last_to_me
      # cr.update!(last_read_message_id: last_to_me.id, last_read_t_ms: last_to_me.t_ms)
      ChatRead.upsert({
        conversation_id: convo.id,
        user_id: current_user.id,
        last_read_message_id: last_to_me.id,
        updated_at: Time.current },
        unique_by: %i[conversation_id user_id])
    end
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { message: "not found" }, status: :not_found
  end

  private
  def require_user!
    render json: { message: "Not authenticated" }, status: :unauthorized unless current_user
  end
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end