// src/doip/DoipActivation.ec
// ISO 13400-2 Routing Activation handshake (0x0005, 0x0006) and connection session management.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "doip.eh"
#include "ec_runtime.h"

#define DOIP_ACTIVATION_REQ_MIN_LEN   7
#define DOIP_ACTIVATION_RESP_LEN      9

// Finds an active or existing session by connection ID
DoipSession* doip_find_session(DoipNode* node, uint32_t connId)
{
   if(!node) return NULL;
   for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
   {
      if(node->sessions[i].connectionId == connId && node->sessions[i].isActivated)
      {
         return &node->sessions[i];
      }
   }
   return NULL;
}

// Closes and frees a session by connection ID
bool doip_close_session(DoipNode* node, uint32_t connId)
{
   if(!node) return false;
   for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
   {
      if(node->sessions[i].connectionId == connId && node->sessions[i].isActivated)
      {
         memset(&node->sessions[i], 0, sizeof(DoipSession));
         if(node->activeSessionCount > 0)
         {
            node->activeSessionCount--;
         }
         return true;
      }
   }
   return false;
}

// Processes a DoIP Routing Activation Request payload and constructs the Response
uint32_t doip_process_routing_activation(DoipNode* node, uint32_t connId, const uint8_t* payload, uint32_t payloadLen, uint8_t* outBuf, uint32_t maxLen)
{
   if(!node || !payload || !outBuf || maxLen < (DOIP_HEADER_SIZE + DOIP_ACTIVATION_RESP_LEN))
   {
      return 0;
   }

   if(payloadLen < DOIP_ACTIVATION_REQ_MIN_LEN)
   {
      return doip_build_generic_nack(DOIP_NACK_INVALID_PAYLOAD_LENGTH, outBuf, maxLen);
   }

   uint16_t clientSa = ((uint16_t)payload[0] << 8) | payload[1];
   uint8_t activationType = payload[2];

   // Validation of Source Address: SA 0x0000 is invalid
   uint8_t respCode = DOIP_ROUTING_SUCCESS;
   if(clientSa == 0x0000)
   {
      respCode = DOIP_ROUTING_ERR_UNKNOWN_SA;
   }

   // Activation Type validation: 0x00 = Default, 0x01 = WWH-OBD
   if(respCode == DOIP_ROUTING_SUCCESS && activationType != 0x00 && activationType != 0x01)
   {
      respCode = DOIP_ROUTING_ERR_UNSUPPORTED_TYPE;
   }

   // Check if this connection ID already holds a session with a different SA
   if(respCode == DOIP_ROUTING_SUCCESS)
   {
      for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
      {
         if(node->sessions[i].isActivated && node->sessions[i].connectionId == connId)
         {
            if(node->sessions[i].clientLogicalAddress != clientSa)
            {
               respCode = DOIP_ROUTING_ERR_SA_DIFFERENT;
               break;
            }
         }
      }
   }

   // Check if this client SA is already registered on another active connection
   if(respCode == DOIP_ROUTING_SUCCESS)
   {
      for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
      {
         if(node->sessions[i].isActivated &&
            node->sessions[i].clientLogicalAddress == clientSa &&
            node->sessions[i].connectionId != connId)
         {
            respCode = DOIP_ROUTING_ERR_SA_ALREADY_REGISTERED;
            break;
         }
      }
   }

   // Allocate or update session slot upon success
   if(respCode == DOIP_ROUTING_SUCCESS)
   {
      DoipSession* slot = NULL;
      // First check if an existing session for connId is being renewed
      for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
      {
         if(node->sessions[i].isActivated && node->sessions[i].connectionId == connId)
         {
            slot = &node->sessions[i];
            break;
         }
      }

      // If not, find first free slot
      if(!slot)
      {
         for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
         {
            if(!node->sessions[i].isActivated)
            {
               slot = &node->sessions[i];
               node->activeSessionCount++;
               break;
            }
         }
      }

      if(!slot)
      {
         respCode = DOIP_ROUTING_ERR_ALL_SOCKETS_REGISTERED;
      }
      else
      {
         slot->connectionId = connId;
         slot->clientLogicalAddress = clientSa;
         slot->activationType = activationType;
         slot->isActivated = true;
         slot->lastActivityMs = 0;
         slot->aliveCheckPending = false;
      }
   }

   // Construct DoIP Routing Activation Response (Type 0x0006, 9 bytes payload)
   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_ROUTING_ACTIVATION_RESPONSE;
   hdr.payloadLength   = DOIP_ACTIVATION_RESP_LEN;

   doip_header_encode(&hdr, outBuf, maxLen);

   uint8_t* p = outBuf + DOIP_HEADER_SIZE;
   // 1. Tester Logical Address (2 bytes)
   p[0] = (uint8_t)((clientSa >> 8) & 0xFF);
   p[1] = (uint8_t)(clientSa & 0xFF);
   // 2. DoIP Entity Logical Address (2 bytes)
   p[2] = (uint8_t)((node->logicalAddress >> 8) & 0xFF);
   p[3] = (uint8_t)(node->logicalAddress & 0xFF);
   // 3. Routing Activation Response Code (1 byte)
   p[4] = respCode;
   // 4. Reserved (4 bytes)
   p[5] = 0x00;
   p[6] = 0x00;
   p[7] = 0x00;
   p[8] = 0x00;

   return DOIP_HEADER_SIZE + DOIP_ACTIVATION_RESP_LEN;
}
