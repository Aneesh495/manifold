// src/secoc/SecOcManager.ec
// AUTOSAR Secure On-Board Communication (SecOC) message authentication and freshness manager.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "secoc.eh"
#include "ec_runtime.h"

// External C fastpath AES-128 CMAC calculation (RFC 4493)
extern void aes128_cmac(const uint8_t* key, const uint8_t* msg, uint32_t len, uint8_t* mac);

#define SECOC_MAX_AUTH_BUFFER (2 + SECOC_MAX_DATA_LEN + 8)

// Generates an AUTOSAR SecOC Message Authentication Code (MAC)
bool secoc_generate_mac(const SecOcConfig* config, const uint8_t* data, uint32_t dataLen, uint64_t freshness, uint8_t* outMac)
{
   if(!config || !data || !outMac || dataLen > SECOC_MAX_DATA_LEN)
   {
      return false;
   }

   // Construct SecOC data to authenticate: DataID (2B) | AuthenticPayload (NB) | FreshnessValue (8B)
   uint8_t authBuf[SECOC_MAX_AUTH_BUFFER];
   uint32_t offset = 0;

   // 1. Data ID (2 bytes, big-endian)
   authBuf[offset++] = (uint8_t)((config->dataId >> 8) & 0xFF);
   authBuf[offset++] = (uint8_t)(config->dataId & 0xFF);

   // 2. Authentic Payload Data
   memcpy(authBuf + offset, data, dataLen);
   offset += dataLen;

   // 3. Freshness Value (8 bytes, big-endian)
   for(int i = 7; i >= 0; i--)
   {
      authBuf[offset++] = (uint8_t)((freshness >> (i * 8)) & 0xFF);
   }

   // 4. Compute full 128-bit AES-CMAC
   uint8_t fullMac[16];
   aes128_cmac(config->key, authBuf, offset, fullMac);

   // 5. Truncate MAC to configured byte length
   uint32_t macBytes = (config->macTruncationBits > 0) ? (config->macTruncationBits / 8) : SECOC_MAC_LEN;
   if(macBytes > 16) macBytes = 16;
   if(macBytes > SECOC_MAC_LEN) macBytes = SECOC_MAC_LEN;

   memcpy(outMac, fullMac, macBytes);
   return true;
}

// Verifies a SecOC MAC using constant-time comparison to prevent timing side-channel attacks
bool secoc_verify_mac(const SecOcConfig* config, const uint8_t* data, uint32_t dataLen, uint64_t freshness, const uint8_t* mac)
{
   if(!config || !data || !mac)
   {
      return false;
   }

   uint8_t expectedMac[SECOC_MAC_LEN];
   if(!secoc_generate_mac(config, data, dataLen, freshness, expectedMac))
   {
      return false;
   }

   uint32_t macBytes = (config->macTruncationBits > 0) ? (config->macTruncationBits / 8) : SECOC_MAC_LEN;
   if(macBytes > SECOC_MAC_LEN) macBytes = SECOC_MAC_LEN;

   // Constant-time comparison
   uint8_t diff = 0;
   for(uint32_t i = 0; i < macBytes; i++)
   {
      diff |= (expectedMac[i] ^ mac[i]);
   }

   return (diff == 0);
}

// Secures an authentic payload into a full SecOcPdu container
bool secoc_secure_pdu(const SecOcConfig* config, const uint8_t* inData, uint32_t inLen, uint64_t freshness, SecOcPdu* outPdu)
{
   if(!config || !inData || !outPdu || inLen > SECOC_MAX_DATA_LEN)
   {
      return false;
   }

   memset(outPdu, 0, sizeof(SecOcPdu));
   memcpy(outPdu->payload, inData, inLen);
   outPdu->payloadLen     = (uint8_t)inLen;
   outPdu->freshnessValue = freshness;

   return secoc_generate_mac(config, inData, inLen, freshness, outPdu->mac);
}

// Verifies the cryptographic integrity and freshness of a received SecOcPdu
bool secoc_verify_pdu(const SecOcConfig* config, const SecOcPdu* inPdu)
{
   if(!config || !inPdu)
   {
      return false;
   }

   return secoc_verify_mac(config, inPdu->payload, inPdu->payloadLen, inPdu->freshnessValue, inPdu->mac);
}
