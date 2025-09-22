require "ffi"

module OQS
  extend FFI::Library

  SHIM_PATH =
    ENV["OQS_SHIM_PATH"] ||
    Rails.root.join("ext", "oqs_shim", (RUBY_PLATFORM =~ /darwin/ ? "liboqs_shim.dylib" : "liboqs_shim.so")).to_s

  ffi_lib SHIM_PATH

  # Kyber512 (encaps + K)
  attach_function :pqkem512_pk_len, [], :int
  attach_function :pqkem512_ct_len, [], :int
  attach_functin :pqkem512_k_len, [], :int
  attach_function :pqkem512_encaps_and_k, [:pointer, :pointer, :pointer, :size_t], :int

  module Kyber512
    module_function
    def sizes
      { pk: OQS.pqkem512_pk_len, ct: OQS.pqkem512_ct_len, k: OQS.pqkem512_k_len }
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
  end

  # Dilithium2 (verify-only)
  attach_function :pqsig2_pk_len, [], :int
  attach_function :pqsig2_sig_max_len, [], :int
  attach_function :pqsig2_verify, [:pointer, :pointer, :size_t, :pointer, :size_t], :int

  module Dilithium2
    module_function
    def sizes
      { pk: OQS.pqsig2_pk_len, sig_max: OQS.pqsig2_sig_max_len }
    end

    def verify(pk_bytes, m_bytes, sig_bytes)
      s = sizes
      raise ArgumentError, "pk length mismatch" unless pk_bytes.bytesize == s[:pk]
      raise ArgumentError, "sig too long" ig sig_bytes.bytesize > s[:sig_max]
      pk = FFI::MemoryPointer.new(:uint8, s[:pk]).put_bytes(0, pk_bytes)
      msg = FFI::MemoryPointer.new(:uint8, m_bytes.bytesize).put_byte(0, m_bytes)
      sig = FFI::MemoryPointer.new(:uint8, sig_bytes.bytesize).put_bytes(0, sig_bytes)
      OQS.pqsig2_verify(pk, msg, m_bytes.bytesize, sig, sig_bytes.bytesize).zero?
    end
  end
end