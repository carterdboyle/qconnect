class Message < ApplicationRecord
  NONCE_BYTES = 16
  
  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"
  belongs_to :conversation

  # --- Validations ---
  validates :t_ms, presence: true,
                    numericality: { only_integer: true, greater_than: 0, less_than: (2**63 - 1) }
  validates :nonce, :ck, :cm, :sig, presence: true
  validate :nonce_exact_length
  
  # Optional: minimal byte-size sanity
  validates :ck, length: { minimum: 1}, if: -> { ck.present? }
  validates :cm, length: { minimum: 1 }, if: -> { cm.present? }
  validates :sig, length: { minimum: 1}, if: -> { sig.present? }

  # --- Scopes ---
  scope :inbox_for, ->(user_or_id) { where(recipient_id: user_or_id.is_a?(User) ? user_or_id.id : user_or_id ).order(created_at: :desc) }
  scope :outbox_for, ->(user_or_id) { where(sender_id: user_or_id.is_a?(User) ? user_or_id.id : user_or_id ).order(created_at: :desc)}
  scope :chronological, ->{ order(Arel.sql("t_ms ASC, id ASC")) }
  scope :recent_first, ->{ order(Arel.sql("t_ms DESC, id DESC")) }

  # --- Helper ---
  
  # bytes that are signed: T || n || CK || CM
  def bytes_for_signature
    Proto.pack_msg(t_ms: t_ms, nonce: nonce, ck: ck, cm: cm)
  end
  
  def as_json_for_api
    {
      id: id,
      from: sender.handle,
      to: recipient.handle,
      t: t_ms,
      n_b64: Base64.urlsafe_encode64(nonce, padding: false),
      ck_b64: Base64.urlsafe_encode64(ck, padding: false),
      cm_b64: Base64.urlsafe_encode64(cm, padding: false),
      s_b64: Base64.urlsafe_encode64(sig, padding: false),
      created_at: created_at&.iso8601
    }
  end

  def verified_by?(public_sign_key_bytes)
    VerificationService.verify(ps: public_sign_key_bytes, m: bytes_for_signature, sig: sig)
  end

  private

  def nonce_exact_length
    return if nonce.blank?
    errors.add(:nonce, "must be #{NONCE_BYTES} bytes") unless nonce.bytesize == NONCE_BYTES
  end

end