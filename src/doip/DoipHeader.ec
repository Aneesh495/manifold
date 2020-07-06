// src/doip/DoipHeader.ec
// ISO 13400-2 DoIP Generic Header encoding, decoding, validation, and NACK generation.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "doip.eh"
#include "ec_runtime.h"

// Encodes an 8-byte DoIP generic header into big-endian wire format
bool doip_header_encode(const DoipHeader* hdr, uint8_t* outBuf, uint32_t maxLen)
{
   if(!hdr || !outBuf || maxLen < DOIP_HEADER_SIZE)
   {
      return false;
   }

   outBuf[0] = hdr->protocolVersion;
   outBuf[1] = hdr->inverseVersion;
   outBuf[2] = (uint8_t)((hdr->payloadType >> 8) & 0xFF);
   outBuf[3] = (uint8_t)(hdr->payloadType & 0xFF);
   outBuf[4] = (uint8_t)((hdr->payloadLength >> 24) & 0xFF);
   outBuf[5] = (uint8_t)((hdr->payloadLength >> 16) & 0xFF);
   outBuf[6] = (uint8_t)((hdr->payloadLength >> 8) & 0xFF);
   outBuf[7] = (uint8_t)(hdr->payloadLength & 0xFF);

   return true;
}

// Decodes and validates an 8-byte DoIP generic header from raw network buffer
bool doip_header_decode(const uint8_t* inBuf, uint32_t inLen, DoipHeader* outHdr, uint8_t* nackCode)
{
   if(!inBuf || !outHdr || inLen < DOIP_HEADER_SIZE)
   {
      if(nackCode) *nackCode = DOIP_NACK_INVALID_PAYLOAD_LENGTH;
      return false;
   }

   uint8_t ver = inBuf[0];
   uint8_t inv = inBuf[1];

   // ISO 13400-2 pattern format validation: inverse version must be bitwise NOT of version
   if((ver ^ inv) != 0xFF)
   {
      if(nackCode) *nackCode = DOIP_NACK_INCORRECT_PATTERN_FORMAT;
      return false;
   }

   // Protocol version verification (ISO 13400-2 specifies 0x02, or default 0xFF during discovery)
   if(ver != DOIP_PROTOCOL_VERSION && ver != 0xFF)
   {
      if(nackCode) *nackCode = DOIP_NACK_INCORRECT_PATTERN_FORMAT;
      return false;
   }

   uint16_t pType = ((uint16_t)inBuf[2] << 8) | inBuf[3];
   uint32_t pLen  = ((uint32_t)inBuf[4] << 24) |
                    ((uint32_t)inBuf[5] << 16) |
                    ((uint32_t)inBuf[6] << 8)  |
                    ((uint32_t)inBuf[7]);

   // Validate payload type against ISO 13400-2 registered types
   bool validType = false;
   switch(pType)
   {
      case DOIP_TYPE_GENERIC_NACK:
      case DOIP_TYPE_VEHICLE_IDENT_REQUEST:
      case DOIP_TYPE_VEHICLE_IDENT_REQUEST_EID:
      case DOIP_TYPE_VEHICLE_IDENT_REQUEST_VIN:
      case DOIP_TYPE_VEHICLE_ANNOUNCEMENT_MESSAGE:
      case DOIP_TYPE_ROUTING_ACTIVATION_REQUEST:
      case DOIP_TYPE_ROUTING_ACTIVATION_RESPONSE:
      case DOIP_TYPE_ALIVE_CHECK_REQUEST:
      case DOIP_TYPE_ALIVE_CHECK_RESPONSE:
      case DOIP_TYPE_ENTITY_STATUS_REQUEST:
      case DOIP_TYPE_ENTITY_STATUS_RESPONSE:
      case DOIP_TYPE_DIAGNOSTIC_POWER_MODE_REQUEST:
      case DOIP_TYPE_DIAGNOSTIC_POWER_MODE_RESPONSE:
      case DOIP_TYPE_DIAGNOSTIC_MESSAGE:
      case DOIP_TYPE_DIAGNOSTIC_POSITIVE_ACK:
      case DOIP_TYPE_DIAGNOSTIC_NEGATIVE_ACK:
         validType = true;
         break;
      default:
         validType = false;
         break;
   }

   if(!validType)
   {
      if(nackCode) *nackCode = DOIP_NACK_UNKNOWN_PAYLOAD_TYPE;
      return false;
   }

   if(pLen > DOIP_MAX_PAYLOAD_SIZE)
   {
      if(nackCode) *nackCode = DOIP_NACK_MESSAGE_TOO_LARGE;
      return false;
   }

   outHdr->protocolVersion = ver;
   outHdr->inverseVersion  = inv;
   outHdr->payloadType     = pType;
   outHdr->payloadLength   = pLen;

   return true;
}

// Builds a DoIP Generic Header NACK response (9 bytes total)
uint32_t doip_build_generic_nack(uint8_t nackCode, uint8_t* outBuf, uint32_t maxLen)
{
   if(!outBuf || maxLen < (DOIP_HEADER_SIZE + 1))
   {
      return 0;
   }

   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_GENERIC_NACK;
   hdr.payloadLength   = 1;

   doip_header_encode(&hdr, outBuf, maxLen);
   outBuf[DOIP_HEADER_SIZE] = nackCode;

   return DOIP_HEADER_SIZE + 1;
}

// Initializes a DoIP node instance with vehicle identity credentials
void doip_node_init(DoipNode* node, const char* vin, uint16_t logicalAddress, const uint8_t* eid, const uint8_t* gid)
{
   if(!node) return;

   memset(node, 0, sizeof(DoipNode));
   if(vin)
   {
      strncpy(node->vin, vin, 17);
   }
   node->logicalAddress = logicalAddress;

   if(eid)
   {
      memcpy(node->eid, eid, 6);
   }
   if(gid)
   {
      memcpy(node->gid, gid, 6);
   }

   node->furtherAction = 0x00; // No further action required
   node->syncStatus = 0x00;    // VIN and GID synchronized
   node->maxPayloadLength = DOIP_MAX_PAYLOAD_SIZE;
   node->aliveCheckTimeoutMs = 500; // 500 ms default alive check response window
   node->activeSessionCount = 0;
}
