// tests/unit/test_core.ec
// Unit tests for core memory buffers, lock-free ring buffer, and bitstream codec.

#include <stdio.h>
#include <assert.h>
#include <string.h>

#include "types.eh"
#include "core.eh"
#include "ec_runtime.h"

bool test_byte_buffer_operations(void)
{
   ByteBuffer buf;
   byte_buffer_init(&buf, 4);

   byte_buffer_append_u8(&buf, 0xAA);
   byte_buffer_append_u16_be(&buf, 0x1234);
   byte_buffer_append_u32_be(&buf, 0xDEADBEEF);

   uint8_t* data = (uint8_t*)buf.rawData;
   assert(data[0] == 0xAA);
   assert(data[1] == 0x12 && data[2] == 0x34);
   assert(data[3] == 0xDE && data[4] == 0xAD && data[5] == 0xBE && data[6] == 0xEF);

   byte_buffer_free(&buf);
   return true;
}

bool test_ring_buffer_operations(void)
{
   RingBuffer* rb = ring_buffer_create(4);
   assert(ring_buffer_is_empty(rb));

   uintptr_t val1 = 101, val2 = 102, val3 = 103, val4 = 104;
   assert(ring_buffer_push(rb, (void*)val1));
   assert(ring_buffer_push(rb, (void*)val2));
   assert(ring_buffer_push(rb, (void*)val3));
   assert(ring_buffer_push(rb, (void*)val4));
   assert(ring_buffer_is_full(rb));

   // Attempting to push to full buffer should fail and increment overrun
   uintptr_t val5 = 105;
   assert(!ring_buffer_push(rb, (void*)val5));
   assert(rb->overrunCount == 1);

   // Pop elements
   assert((uintptr_t)ring_buffer_pop(rb) == 101);
   assert((uintptr_t)ring_buffer_pop(rb) == 102);
   assert(ring_buffer_size(rb) == 2);

   // Push new element after wrap-around
   assert(ring_buffer_push(rb, (void*)val5));
   assert((uintptr_t)ring_buffer_pop(rb) == 103);
   assert((uintptr_t)ring_buffer_pop(rb) == 104);
   assert((uintptr_t)ring_buffer_pop(rb) == 105);
   assert(ring_buffer_is_empty(rb));

   ring_buffer_destroy(rb, NULL);
   return true;
}

bool test_bitstream_intel_and_motorola(void)
{
   uint8_t payload[8] = { 0 };

   // Test 1: Intel 12-bit unsigned injection and extraction
   // Inject 0xABC (2748) at startBit 4
   assert(bitstream_inject_unsigned(payload, 8, 4, 12, ENDIAN_INTEL, 0xABC));
   uint64_t extractedIntel = bitstream_extract_unsigned(payload, 8, 4, 12, ENDIAN_INTEL);
   assert(extractedIntel == 0xABC);

   // Test 2: Intel signed negative extraction
   // 12-bit signed: 0xFFF is -1
   memset(payload, 0, sizeof(payload));
   assert(bitstream_inject_unsigned(payload, 8, 0, 12, ENDIAN_INTEL, 0xFFF));
   int64_t signedVal = bitstream_extract_signed(payload, 8, 0, 12, ENDIAN_INTEL);
   assert(signedVal == -1);

   // Test 3: Motorola bitstream injection and extraction across byte boundary
   memset(payload, 0, sizeof(payload));
   // In DBC Motorola standard, startBit 7 (MSB of byte 0), length 14
   uint64_t motoVal = 0x2A5B; // 14-bit value: 10 1010 0101 1011
   assert(bitstream_inject_unsigned(payload, 8, 7, 14, ENDIAN_MOTOROLA, motoVal));
   uint64_t extractedMoto = bitstream_extract_unsigned(payload, 8, 7, 14, ENDIAN_MOTOROLA);
   assert(extractedMoto == motoVal);

   return true;
}
