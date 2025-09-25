module Proto
  module_function
  def be64(n) = [n].pack("Q>") # 8-byte big endian
  def pack_contact_msg(t_ms:, nonce:, peer_ps:) # -> String (bytes)
    raise ArgumentError, "nonce 16B" unless nonce.bytesize == 16
    be64(t_ms) + nonce + peer_ps
  end
  
  def pack_msg(t_ms:, nonce:, ck:, cm:)
    raise ArugmentError, "nonce 16B" unless nonce.bytesize == 16
    be64(t_ms) + nonce + ck + cm
  end
end