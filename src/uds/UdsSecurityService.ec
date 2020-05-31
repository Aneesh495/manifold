// src/uds/UdsSecurityService.ec
// ISO 14229-1 Service 0x27: SecurityAccess multi-level cryptographic challenge-response.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations from UdsPdu.ec
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);
bool uds_is_suppress_pos_rsp(uint8_t subfunction);
uint8_t uds_get_clean_subfunction(uint8_t subfunction);

#define UDS_SECURITY_MAX_ATTEMPTS 3
#define UDS_SECURITY_LOCKOUT_MS   10000 // 10 seconds lockout

// Cryptographic key derivation function from seed and level
uint32_t uds_compute_key_from_seed(uint32_t seed, uint8_t level)
{
   // Non-linear Galois transform with level-dependent constant masking
   static const uint32_t level_salts[8] = {
      0x5A827999U, 0x6ED9EBA1U, 0x8F1BBCDCU, 0xCA62C1D6U,
      0x13579BDFU, 0x2468ACE0U, 0xFEDCBA98U, 0x76543210U
   };

   uint32_t salt = level_salts[level & 0x07];
   uint32_t key = seed ^ salt;

   for(int i = 0; i < 32; i++)
   {
      bool msb = (key >> 31) & 1;
      key = (key << 1) ^ (msb ? 0x04C11DB7U : 0);
   }

   return key ^ salt;
}

// Pseudo-random seed generation with microsecond entropy
static uint32_t generate_seed(void)
{
   uint64_t t = ec_get_time_us();
   uint32_t seed = (uint32_t)(t ^ (t >> 32) ^ 0x9E3779B97F4A7C15ULL);
   if(seed == 0) seed = 0x12345678; // Seed must never be zero
   return seed;
}

// Handles Service 0x27: SecurityAccess
uint32_t uds_handle_security_access(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp) return 0;

   if(reqLen < 2)
   {
      return uds_build_negative_response(UDS_SID_SECURITY_ACCESS,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint64_t nowMs = ec_get_time_ms();
   if(nowMs < server->security.lockoutUntilMs)
   {
      return uds_build_negative_response(UDS_SID_SECURITY_ACCESS,
                                         NRC_REQUIRED_TIME_DELAY_NOT_EXPIRED,
                                         resp, maxRespLen);
   }

   uint8_t rawSub = req[1];
   uint8_t sub = uds_get_clean_subfunction(rawSub);
   bool suppressPos = uds_is_suppress_pos_rsp(rawSub);

   if((sub % 2) != 0)
   {
      // Odd subfunction: RequestSeed (0x01, 0x03, 0x05, etc.)
      uint8_t reqLevel = sub; // e.g. Level 1 = 0x01, Level 3 = 0x03

      if(server->security.currentLevel == reqLevel)
      {
         // Already unlocked: return seed of all zeroes per ISO 14229-1
         if(suppressPos) return 0;
         if(maxRespLen < 6) return 0;

         resp[0] = UDS_SID_SECURITY_ACCESS + 0x40; // 0x67
         resp[1] = sub;
         resp[2] = 0x00;
         resp[3] = 0x00;
         resp[4] = 0x00;
         resp[5] = 0x00;
         return 6;
      }

      // Generate active cryptographic seed
      server->security.activeSeed = generate_seed();
      server->security.seedGenerated = true;

      if(suppressPos) return 0;
      if(maxRespLen < 6) return 0;

      resp[0] = UDS_SID_SECURITY_ACCESS + 0x40;
      resp[1] = sub;
      resp[2] = (uint8_t)((server->security.activeSeed >> 24) & 0xFF);
      resp[3] = (uint8_t)((server->security.activeSeed >> 16) & 0xFF);
      resp[4] = (uint8_t)((server->security.activeSeed >> 8) & 0xFF);
      resp[5] = (uint8_t)(server->security.activeSeed & 0xFF);
      return 6;
   }
   else
   {
      // Even subfunction: SendKey (0x02, 0x04, 0x06, etc.)
      if(!server->security.seedGenerated)
      {
         return uds_build_negative_response(UDS_SID_SECURITY_ACCESS,
                                            NRC_REQUEST_SEQUENCE_ERROR,
                                            resp, maxRespLen);
      }

      if(reqLen < 6)
      {
         return uds_build_negative_response(UDS_SID_SECURITY_ACCESS,
                                            NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                            resp, maxRespLen);
      }

      uint32_t providedKey = ((uint32_t)req[2] << 24) |
                             ((uint32_t)req[3] << 16) |
                             ((uint32_t)req[4] << 8)  |
                             ((uint32_t)req[5]);

      uint8_t targetLevel = sub - 1; // e.g. 0x02 validates level 1
      uint32_t expectedKey = uds_compute_key_from_seed(server->security.activeSeed, targetLevel);

      // Invalidate active seed to prevent replay attacks
      server->security.seedGenerated = false;

      if(providedKey == expectedKey)
      {
         // Key is valid: unlock security level
         server->security.currentLevel = targetLevel;
         server->security.failedAttempts = 0;

         if(suppressPos) return 0;
         if(maxRespLen < 2) return 0;

         resp[0] = UDS_SID_SECURITY_ACCESS + 0x40;
         resp[1] = sub;
         return 2;
      }
      else
      {
         // Key mismatch
         server->security.failedAttempts++;
         if(server->security.failedAttempts >= UDS_SECURITY_MAX_ATTEMPTS)
         {
            server->security.lockoutUntilMs = ec_get_time_ms() + UDS_SECURITY_LOCKOUT_MS;
            return uds_build_negative_response(UDS_SID_SECURITY_ACCESS,
                                               NRC_EXCEEDED_NUMBER_OF_ATTEMPTS,
                                               resp, maxRespLen);
         }
         return uds_build_negative_response(UDS_SID_SECURITY_ACCESS,
                                            NRC_INVALID_KEY,
                                            resp, maxRespLen);
      }
   }
}
