// src/doip/DoipRouter.ec
// ISO 13400-2 Diagnostic message encapsulation (0x8001), ACK (0x8002), NACK (0x8003), and logical routing.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "doip.eh"
#include "ec_runtime.h"

#define DOIP_DIAG_HEADER_LEN 4 // 2 bytes SA + 2 bytes TA

// Constructs an ISO 13400-2 Diagnostic Message Positive ACK (Type 0x8002)
uint32_t doip_build_diagnostic_ack(uint16_t sourceAddr, uint16_t targetAddr, uint8_t ackCode, const uint8_t* prevData, uint32_t prevDataLen, uint8_t* outBuf, uint32_t maxLen)
{
   uint32_t payloadLen = DOIP_DIAG_HEADER_LEN + 1 + prevDataLen;
   if(!outBuf || maxLen < (DOIP_HEADER_SIZE + payloadLen))
   {
      return 0;
   }

   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_DIAGNOSTIC_POSITIVE_ACK;
   hdr.payloadLength   = payloadLen;

   if(!doip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   uint8_t* p = outBuf + DOIP_HEADER_SIZE;
   p[0] = (uint8_t)((sourceAddr >> 8) & 0xFF);
   p[1] = (uint8_t)(sourceAddr & 0xFF);
   p[2] = (uint8_t)((targetAddr >> 8) & 0xFF);
   p[3] = (uint8_t)(targetAddr & 0xFF);
   p[4] = ackCode;

   if(prevData && prevDataLen > 0)
   {
      memcpy(p + 5, prevData, prevDataLen);
   }

   return DOIP_HEADER_SIZE + payloadLen;
}

// Constructs an ISO 13400-2 Diagnostic Message Negative ACK (Type 0x8003)
uint32_t doip_build_diagnostic_nack(uint16_t sourceAddr, uint16_t targetAddr, uint8_t nackCode, const uint8_t* prevData, uint32_t prevDataLen, uint8_t* outBuf, uint32_t maxLen)
{
   uint32_t payloadLen = DOIP_DIAG_HEADER_LEN + 1 + prevDataLen;
   if(!outBuf || maxLen < (DOIP_HEADER_SIZE + payloadLen))
   {
      return 0;
   }

   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_DIAGNOSTIC_NEGATIVE_ACK;
   hdr.payloadLength   = payloadLen;

   if(!doip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   uint8_t* p = outBuf + DOIP_HEADER_SIZE;
   p[0] = (uint8_t)((sourceAddr >> 8) & 0xFF);
   p[1] = (uint8_t)(sourceAddr & 0xFF);
   p[2] = (uint8_t)((targetAddr >> 8) & 0xFF);
   p[3] = (uint8_t)(targetAddr & 0xFF);
   p[4] = nackCode;

   if(prevData && prevDataLen > 0)
   {
      memcpy(p + 5, prevData, prevDataLen);
   }

   return DOIP_HEADER_SIZE + payloadLen;
}

// Decapsulates incoming DoIP Diagnostic Message (0x8001), validates session routing,
// delegates UDS processing, and encapsulates the diagnostic response.
uint32_t doip_process_diagnostic_message(DoipNode* node, uint32_t connId, const uint8_t* payload, uint32_t payloadLen, uint8_t* outBuf, uint32_t maxLen, DoipUdsHandler udsCallback)
{
   if(!node || !payload || !outBuf)
   {
      return 0;
   }

   DoipSession* session = doip_find_session(node, connId);
   if(!session || !session->isActivated)
   {
      // Unactivated socket cannot transmit diagnostic messages
      return 0;
   }

   if(payloadLen < (DOIP_DIAG_HEADER_LEN + 1))
   {
      return doip_build_generic_nack(DOIP_NACK_INVALID_PAYLOAD_LENGTH, outBuf, maxLen);
   }

   uint16_t sa = ((uint16_t)payload[0] << 8) | payload[1];
   uint16_t ta = ((uint16_t)payload[2] << 8) | payload[3];

   // Verify source address matches the activated session SA
   if(sa != session->clientLogicalAddress)
   {
      return doip_build_diagnostic_nack(node->logicalAddress, sa, DOIP_DIAG_NACK_INVALID_SOURCE_ADDRESS, NULL, 0, outBuf, maxLen);
   }

   // Verify target address is known (either this DoIP entity or target vehicle ECU)
   if(ta != node->logicalAddress && ta != 0x0E00 && ta != 0x0E01 && ta != 0xE400)
   {
      return doip_build_diagnostic_nack(node->logicalAddress, sa, DOIP_DIAG_NACK_UNKNOWN_TARGET_ADDRESS, NULL, 0, outBuf, maxLen);
   }

   const uint8_t* udsReq = payload + DOIP_DIAG_HEADER_LEN;
   uint32_t udsReqLen = payloadLen - DOIP_DIAG_HEADER_LEN;

   uint8_t udsRespBuf[DOIP_MAX_PAYLOAD_SIZE];
   uint32_t udsRespLen = 0;

   if(udsCallback)
   {
      udsCallback(sa, ta, udsReq, udsReqLen, udsRespBuf, &udsRespLen, sizeof(udsRespBuf));
   }

   if(udsRespLen == 0)
   {
      return 0;
   }

   // Encapsulate UDS response inside DoIP Diagnostic Message (0x8001)
   uint32_t respPayloadLen = DOIP_DIAG_HEADER_LEN + udsRespLen;
   if(maxLen < (DOIP_HEADER_SIZE + respPayloadLen))
   {
      return doip_build_diagnostic_nack(node->logicalAddress, sa, DOIP_DIAG_NACK_MESSAGE_TOO_LARGE, NULL, 0, outBuf, maxLen);
   }

   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_DIAGNOSTIC_MESSAGE;
   hdr.payloadLength   = respPayloadLen;

   doip_header_encode(&hdr, outBuf, maxLen);

   uint8_t* p = outBuf + DOIP_HEADER_SIZE;
   // In response, SA is responder (node->logicalAddress or ta), TA is tester (sa)
   p[0] = (uint8_t)((ta >> 8) & 0xFF);
   p[1] = (uint8_t)(ta & 0xFF);
   p[2] = (uint8_t)((sa >> 8) & 0xFF);
   p[3] = (uint8_t)(sa & 0xFF);
   memcpy(p + DOIP_DIAG_HEADER_LEN, udsRespBuf, udsRespLen);

   return DOIP_HEADER_SIZE + respPayloadLen;
}
