// include/secoc.eh
// AUTOSAR Secure On-Board Communication (SecOC) message authentication definitions.

#ifndef MANIFOLD_SECOC_EH
#define MANIFOLD_SECOC_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define SECOC_MAX_DATA_LEN 64
#define SECOC_MAC_LEN 8

typedef struct SecOcPdu
{
   uint8_t payload[SECOC_MAX_DATA_LEN];
   uint8_t payloadLen;
   uint64_t freshnessValue;
   uint8_t mac[SECOC_MAC_LEN];
} SecOcPdu;

typedef struct SecOcConfig
{
   uint16_t dataId;
   uint8_t key[16];          // 128-bit symmetric key
   uint8_t macTruncationBits;
   uint8_t freshnessBits;
} SecOcConfig;

bool secoc_generate_mac(const SecOcConfig* config, const uint8_t* data, uint32_t dataLen,
                        uint64_t freshness, uint8_t* outMac);
bool secoc_verify_mac(const SecOcConfig* config, const uint8_t* data, uint32_t dataLen,
                      uint64_t freshness, const uint8_t* mac);
bool secoc_secure_pdu(const SecOcConfig* config, const uint8_t* inData, uint32_t inLen,
                      uint64_t freshness, SecOcPdu* outPdu);
bool secoc_verify_pdu(const SecOcConfig* config, const SecOcPdu* inPdu);

#endif // MANIFOLD_SECOC_EH
