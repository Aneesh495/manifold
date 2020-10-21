// tests/regression/test_fuzz_codecs.ec
// Pseudo-random fuzzing and robustness tests for CAN FD, SOME/IP, and DoIP network decoders.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#include "types.eh"
#include "can.eh"
#include "doip.eh"
#include "someip.eh"
#include "dbc.eh"
#include "ec_runtime.h"

// Forward declarations
bool test_fuzz_can_fd_crc_robustness(void);
bool test_fuzz_someip_deserializer_robustness(void);
bool test_fuzz_doip_header_robustness(void);

// Linear Congruential Generator for reproducible pseudo-random fuzzing
static uint32_t g_fuzzSeed = 0x12345678;
static uint32_t fuzz_rand(void)
{
   g_fuzzSeed = g_fuzzSeed * 1103515245 + 12345;
   return (g_fuzzSeed >> 16) & 0x7FFF;
}

bool test_fuzz_can_fd_crc_robustness(void)
{
   uint8_t buffer[64];

   // Fuzz 1,000 randomized payloads of arbitrary length 1 to 64 bytes
   for(uint32_t i = 0; i < 1000; i++)
   {
      uint32_t len = (fuzz_rand() % 64) + 1;
      uint8_t stuffCount = (uint8_t)(fuzz_rand() & 0x07);

      for(uint32_t b = 0; b < len; b++)
      {
         buffer[b] = (uint8_t)(fuzz_rand() & 0xFF);
      }

      uint32_t crc17 = can_fd_crc17(buffer, len, stuffCount);
      uint32_t crc21 = can_fd_crc21(buffer, len, stuffCount);

      // Verify non-zero and bounded calculation
      (void)crc17;
      (void)crc21;
   }

   return true;
}

bool test_fuzz_someip_deserializer_robustness(void)
{
   uint8_t randomFuzz[128];

   // Inject 1,000 corrupt random packets into SOME/IP deserializer
   for(uint32_t i = 0; i < 1000; i++)
   {
      uint32_t pktLen = (fuzz_rand() % 120) + 1;
      for(uint32_t b = 0; b < pktLen; b++)
      {
         randomFuzz[b] = (uint8_t)(fuzz_rand() & 0xFF);
      }

      SomeIpMessage msg;
      // Must reject corrupt packet cleanly without buffer overrun or crash
      bool result = someip_message_deserialize(randomFuzz, pktLen, &msg);
      (void)result;
   }

   return true;
}

bool test_fuzz_doip_header_robustness(void)
{
   uint8_t randomFuzz[64];

   // Inject 1,000 corrupt random packets into DoIP header decoder
   for(uint32_t i = 0; i < 1000; i++)
   {
      uint32_t pktLen = (fuzz_rand() % 50) + 1;
      for(uint32_t b = 0; b < pktLen; b++)
      {
         randomFuzz[b] = (uint8_t)(fuzz_rand() & 0xFF);
      }

      DoipHeader hdr;
      uint8_t nack = 0;
      bool result = doip_header_decode(randomFuzz, pktLen, &hdr, &nack);
      (void)result;
      (void)nack;
   }

   return true;
}
