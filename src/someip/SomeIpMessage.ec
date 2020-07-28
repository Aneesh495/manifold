// src/someip/SomeIpMessage.ec
// AUTOSAR SOME/IP message serialization, deserialization, and header validation.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "someip.eh"
#include "ec_runtime.h"

// Encodes a 16-byte SOME/IP header into big-endian wire format
bool someip_header_encode(const SomeIpHeader* hdr, uint8_t* outBuf, uint32_t maxLen)
{
   if(!hdr || !outBuf || maxLen < SOMEIP_HEADER_SIZE)
   {
      return false;
   }

   outBuf[0]  = (uint8_t)((hdr->serviceId >> 8) & 0xFF);
   outBuf[1]  = (uint8_t)(hdr->serviceId & 0xFF);
   outBuf[2]  = (uint8_t)((hdr->methodId >> 8) & 0xFF);
   outBuf[3]  = (uint8_t)(hdr->methodId & 0xFF);
   outBuf[4]  = (uint8_t)((hdr->length >> 24) & 0xFF);
   outBuf[5]  = (uint8_t)((hdr->length >> 16) & 0xFF);
   outBuf[6]  = (uint8_t)((hdr->length >> 8) & 0xFF);
   outBuf[7]  = (uint8_t)(hdr->length & 0xFF);
   outBuf[8]  = (uint8_t)((hdr->clientId >> 8) & 0xFF);
   outBuf[9]  = (uint8_t)(hdr->clientId & 0xFF);
   outBuf[10] = (uint8_t)((hdr->sessionId >> 8) & 0xFF);
   outBuf[11] = (uint8_t)(hdr->sessionId & 0xFF);
   outBuf[12] = hdr->protocolVersion;
   outBuf[13] = hdr->interfaceVersion;
   outBuf[14] = hdr->messageType;
   outBuf[15] = hdr->returnCode;

   return true;
}

// Decodes a 16-byte SOME/IP header from network wire buffer
bool someip_header_decode(const uint8_t* inBuf, uint32_t inLen, SomeIpHeader* outHdr)
{
   if(!inBuf || !outHdr || inLen < SOMEIP_HEADER_SIZE)
   {
      return false;
   }

   outHdr->serviceId        = ((uint16_t)inBuf[0] << 8) | inBuf[1];
   outHdr->methodId         = ((uint16_t)inBuf[2] << 8) | inBuf[3];
   outHdr->length           = ((uint32_t)inBuf[4] << 24) |
                              ((uint32_t)inBuf[5] << 16) |
                              ((uint32_t)inBuf[6] << 8)  |
                              ((uint32_t)inBuf[7]);
   outHdr->clientId         = ((uint16_t)inBuf[8] << 8) | inBuf[9];
   outHdr->sessionId        = ((uint16_t)inBuf[10] << 8) | inBuf[11];
   outHdr->protocolVersion  = inBuf[12];
   outHdr->interfaceVersion = inBuf[13];
   outHdr->messageType      = inBuf[14];
   outHdr->returnCode       = inBuf[15];

   // AUTOSAR SOME/IP length verification: must be at least 8 (covers client ID to return code)
   if(outHdr->length < 8)
   {
      return false;
   }

   return true;
}

// Serializes a full SOME/IP message (header + payload) into network buffer
uint32_t someip_message_serialize(const SomeIpMessage* msg, uint8_t* outBuf, uint32_t maxLen)
{
   if(!msg || !outBuf)
   {
      return 0;
   }

   uint32_t totalLen = SOMEIP_HEADER_SIZE + msg->payloadLength;
   if(maxLen < totalLen)
   {
      return 0;
   }

   SomeIpHeader hdr = msg->header;
   hdr.length = msg->payloadLength + 8; // AUTOSAR: length field includes 8 bytes of header remainder

   if(!someip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   if(msg->payloadLength > 0)
   {
      memcpy(outBuf + SOMEIP_HEADER_SIZE, msg->payload, msg->payloadLength);
   }

   return totalLen;
}

// Deserializes a full SOME/IP message from raw network buffer
bool someip_message_deserialize(const uint8_t* inBuf, uint32_t inLen, SomeIpMessage* outMsg)
{
   if(!inBuf || !outMsg || inLen < SOMEIP_HEADER_SIZE)
   {
      return false;
   }

   if(!someip_header_decode(inBuf, inLen, &outMsg->header))
   {
      return false;
   }

   uint32_t payloadLen = outMsg->header.length - 8;
   if((SOMEIP_HEADER_SIZE + payloadLen) > inLen)
   {
      return false;
   }

   if(payloadLen > SOMEIP_PAYLOAD_MAX)
   {
      return false;
   }

   outMsg->payloadLength = payloadLen;
   if(payloadLen > 0)
   {
      memcpy(outMsg->payload, inBuf + SOMEIP_HEADER_SIZE, payloadLen);
   }

   return true;
}

// Initializes a SOME/IP response message based on the corresponding request
void someip_message_init_response(const SomeIpMessage* req, SomeIpMessage* resp, uint8_t returnCode)
{
   if(!req || !resp) return;

   memset(resp, 0, sizeof(SomeIpMessage));
   resp->header.serviceId        = req->header.serviceId;
   resp->header.methodId         = req->header.methodId;
   resp->header.clientId         = req->header.clientId;
   resp->header.sessionId        = req->header.sessionId;
   resp->header.protocolVersion  = req->header.protocolVersion;
   resp->header.interfaceVersion = req->header.interfaceVersion;
   resp->header.messageType      = (returnCode == SOMEIP_RET_E_OK) ? SOMEIP_MSG_RESPONSE : SOMEIP_MSG_ERROR;
   resp->header.returnCode       = returnCode;
   resp->header.length           = 8; // 8 bytes remainder with empty payload initially
   resp->payloadLength           = 0;
}
