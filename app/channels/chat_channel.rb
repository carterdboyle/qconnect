# frozen_string_literal: true
class ChatChannel < ApplicationCable::Channel
  def subscribed
    convo_id = params[:conversation_id]
    reject unless convo_id.present?
    stream_from "chat:#{convo_id}"
  end
end