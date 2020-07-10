// src/doip/DoipDiscovery.ec
// ISO 13400-2 Vehicle Identification and Announcement message handler.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "doip.eh"
#include "ec_runtime.h"

#define DOIP_VIN_LENGTH              17
#define DOIP_EID_LENGTH              6
#define DOIP_GID_LENGTH              6
#define DOIP_ANNOUNCEMENT_PAYLOAD_LEN 33

// Constructs an ISO 13400-2 Vehicle Announcement / Identification Response frame (41 bytes total)
uint32_t doip_build_vehicle_announcement(const DoipNode* node, uint8_t* outBuf, uint32_t maxLen)
{
   if(!node || !outBuf || maxLen < (DOIP_HEADER_SIZE + DOIP_ANNOUNCEMENT_PAYLOAD_LEN))
   {
      return 0;
   }

   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_VEHICLE_ANNOUNCEMENT_MESSAGE;
   hdr.payloadLength   = DOIP_ANNOUNCEMENT_PAYLOAD_LEN;

   if(!doip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   uint8_t* p = outBuf + DOIP_HEADER_SIZE;

   // 1. VIN (17 bytes)
   uint32_t vinLen = (uint32_t)strlen(node->vin);
   for(uint32_t i = 0; i < DOIP_VIN_LENGTH; i++)
   {
      p[i] = (i < vinLen) ? (uint8_t)node->vin[i] : (uint8_t)'0';
   }
   p += DOIP_VIN_LENGTH;

   // 2. Logical Address (2 bytes, big-endian)
   p[0] = (uint8_t)((node->logicalAddress >> 8) & 0xFF);
   p[1] = (uint8_t)(node->logicalAddress & 0xFF);
   p += 2;

   // 3. EID (Entity ID / MAC address, 6 bytes)
   memcpy(p, node->eid, DOIP_EID_LENGTH);
   p += DOIP_EID_LENGTH;

   // 4. GID (Group ID, 6 bytes)
   memcpy(p, node->gid, DOIP_GID_LENGTH);
   p += DOIP_GID_LENGTH;

   // 5. Further Action Required (1 byte)
   p[0] = node->furtherAction;
   p += 1;

   // 6. VIN/GID Synchronization Status (1 byte)
   p[0] = node->syncStatus;

   return DOIP_HEADER_SIZE + DOIP_ANNOUNCEMENT_PAYLOAD_LEN;
}

// Processes incoming Vehicle Identification Requests (Types 0x0001, 0x0002, 0x0003)
// and generates Vehicle Announcement if addressing criteria match.
uint32_t doip_handle_vehicle_ident_request(const DoipNode* node, const uint8_t* inBuf, uint32_t inLen, uint8_t* outBuf, uint32_t maxLen)
{
   if(!node || !inBuf || !outBuf || inLen < DOIP_HEADER_SIZE)
   {
      return 0;
   }

   DoipHeader hdr;
   uint8_t nack = 0;
   if(!doip_header_decode(inBuf, inLen, &hdr, &nack))
   {
      return doip_build_generic_nack(nack, outBuf, maxLen);
   }

   const uint8_t* payload = inBuf + DOIP_HEADER_SIZE;
   uint32_t availPayload = inLen - DOIP_HEADER_SIZE;

   if(availPayload < hdr.payloadLength)
   {
      return doip_build_generic_nack(DOIP_NACK_INVALID_PAYLOAD_LENGTH, outBuf, maxLen);
   }

   switch(hdr.payloadType)
   {
      case DOIP_TYPE_VEHICLE_IDENT_REQUEST:
      {
         // Type 0x0001: General broadcast request (payload length 0)
         return doip_build_vehicle_announcement(node, outBuf, maxLen);
      }

      case DOIP_TYPE_VEHICLE_IDENT_REQUEST_EID:
      {
         // Type 0x0002: Filtered by EID (payload length 6)
         if(hdr.payloadLength != DOIP_EID_LENGTH)
         {
            return doip_build_generic_nack(DOIP_NACK_INVALID_PAYLOAD_LENGTH, outBuf, maxLen);
         }
         if(memcmp(payload, node->eid, DOIP_EID_LENGTH) == 0)
         {
            return doip_build_vehicle_announcement(node, outBuf, maxLen);
         }
         return 0; // Filter mismatch: do not respond
      }

      case DOIP_TYPE_VEHICLE_IDENT_REQUEST_VIN:
      {
         // Type 0x0003: Filtered by VIN (payload length 17)
         if(hdr.payloadLength != DOIP_VIN_LENGTH)
         {
            return doip_build_generic_nack(DOIP_NACK_INVALID_PAYLOAD_LENGTH, outBuf, maxLen);
         }
         if(memcmp(payload, node->vin, DOIP_VIN_LENGTH) == 0)
         {
            return doip_build_vehicle_announcement(node, outBuf, maxLen);
         }
         return 0; // Filter mismatch: do not respond
      }

      default:
         return 0;
   }
}
