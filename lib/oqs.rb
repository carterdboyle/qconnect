require "ffi"

module OQS
  extend FFI::Library

  SHIM_PATH =
    ENV["OQS_SHIM_PATH"] ||
    Rails.root.join("ext", "oqs_shim", (RUBY_PLATFORM =~ /darwin/ ? "liboqs_shim.dylib" : "liboqs_shim.so")).to_s

  ffi_lib SHIM_PATH

  # Kyber512 (encaps + K)
  attach_function :pqkem512_keypair, [ :pointer, :pointer ], :int
  attach_function :pqkem512_pk_len, [], :int
  attach_function :pqkem512_sk_len, [], :int
  attach_function :pqkem512_ct_len, [], :int
  attach_function :pqkem512_k_len, [], :int
  attach_function :pqkem512_encaps_and_k, [:pointer, :pointer, :pointer, :size_t], :int
  attach_function :pqkem512_decaps_and_k, [:pointer, :pointer, :pointer, :size_t], :int
  attach_function :pqkem512_name, [:pointer, :size_t], :int

  module Kyber512
    module_function
    def sizes
      { pk: OQS.pqkem512_pk_len, sk: OQS.pqkem512_sk_len, ct: OQS.pqkem512_ct_len, k: OQS.pqkem512_k_len }
    end

    def keypair
      s = sizes
      pk = FFI::MemoryPointer.new(:uint8, s[:pk])
      sk = FFI::MemoryPointer.new(:uint8, s[:sk])
      rc = OQS.pqkem512_keypair(pk, sk)
      raise "pqkem512 keygen failed rc=#{rc}" unless rc.zero?
      return [pk.read_string_length(s[:pk]), sk.read_string_length(s[:sk])]
    end

    def kem_name
      buf = FFI::MemoryPointer.new(:char, 64)
      rc = OQS.pqkem512_name(buf, 64)
      raise "kem_name failed (rc=#{rc})" unless rc.zero?
      buf.read_string
    end

    def encaps_and_k(pk_bytes)
      s = sizes
      raise ArgumentError, "pk length mismatch" unless pk_bytes.bytesize == s[:pk]
      pk = FFI::MemoryPointer.new(:uint8, s[:pk]).put_bytes(0, pk_bytes)
      ct = FFI::MemoryPointer.new(:uint8, s[:ct])
      k = FFI::MemoryPointer.new(:uint8, s[:k])
      rc = OQS.pqkem512_encaps_and_k(pk, ct, k, s[:k])
      raise "pqkem512_encaps_and_k failed (rc=#{rc})" unless rc.zero?
      [ct.read_string_length(s[:ct]), k.read_string_length(s[:k])]
    end

    def decaps(sk_bytes, ct_bytes)
      s = sizes
      raise ArgumentError, "sk length mismatch" unless sk_bytes.bytesize == s[:sk]
      sk = FFI::MemoryPointer.new(:uint8, s[:sk]).put_bytes(0, sk_bytes)
      ct = FFI::MemoryPointer.new(:uint8, s[:ct]).put_bytes(0, ct_bytes)
      k = FFI::MemoryPointer.new(:uint8, s[:k])
      rc = OQS.pqkem512_decaps_and_k(sk, ct, k, s[:k])
      raise "pqkem512_decaps_and_k failed (rc=#{rc})" unless rc.zero?
      k.read_string_length(s[:k])
    end
  end

  # Dilithium2 (verify-only)
  attach_function :pqsig2_keypair, [:pointer, :pointer], :int
  attach_function :pqsig2_pk_len, [], :int
  attach_function :pqsig2_sk_len, [], :int
  attach_function :pqsig2_sig_max_len, [], :int
  attach_function :pqsig2_sign, [:pointer, :pointer, :pointer, :size_t, :pointer], :int
  attach_function :pqsig2_verify, [:pointer, :pointer, :size_t, :pointer, :size_t], :int


  module Dilithium2
    module_function
    def sizes
      { sk: OQS.pqsig2_sk_len, pk: OQS.pqsig2_pk_len, sig_max: OQS.pqsig2_sig_max_len }
    end

    def keypair
      s = sizes
      pk = FFI::MemoryPointer.new(:uint8, s[:pk])
      sk = FFI::MemoryPointer.new(:uint8, s[:sk])
      rc = OQS.pqsig2_keypair(pk, sk)
      raise "pqsig2_keygen failed (rc=#{rc})" unless rc.zero?
      return [pk.read_string_length(s[:pk]), sk.read_string_length(s[:sk])]
    end

    def sign(sk_bytes, m_bytes)
      s = sizes
      raise ArgumentError, "sk length mismatch" unless sk_bytes.bytesize == s[:sk]
      sk = FFI::MemoryPointer.new(:uint8, s[:sk]).put_bytes(0, sk_bytes)
      msg = FFI::MemoryPointer.new(:uint8, m_bytes.bytesize).put_bytes(0, m_bytes)
      sig = FFI::MemoryPointer.new(:uint8, s[:sig_max])
      sig_len = FFI::MemoryPointer.new(:size_t)
      rc = OQS.pqsig2_sign(sig, sig_len, msg, m_bytes.bytesize, sk)
      raise "pqsig2_sign failed (rc=#{rc})" unless rc.zero?

      actual_len = if FFI.type_size(:size_t) == 8
        sig_len.get_uint64(0)
      else
        sig_len.get_uint32(0)
      end

      return sig.read_string_length(actual_len)
    end

    def verify(pk_bytes, m_bytes, sig_bytes)
      s = sizes
      raise ArgumentError, "pk length mismatch" unless pk_bytes.bytesize == s[:pk]
      raise ArgumentError, "sig too long" if sig_bytes.bytesize > s[:sig_max]
      pk = FFI::MemoryPointer.new(:uint8, s[:pk]).put_bytes(0, pk_bytes)
      msg = FFI::MemoryPointer.new(:uint8, m_bytes.bytesize).put_bytes(0, m_bytes)
      sig = FFI::MemoryPointer.new(:uint8, sig_bytes.bytesize).put_bytes(0, sig_bytes)
      OQS.pqsig2_verify(pk, msg, m_bytes.bytesize, sig, sig_bytes.bytesize).zero?
    end
  end
end