class NonceLedger
  # returns true on first-seen, false if already present
  def self.consume!(signer_ps:, nonce:)
    UsedNonce.create!(signer_ps:, nonce:, seen_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end