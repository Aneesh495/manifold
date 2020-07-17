// src/doip/DoipAliveCheck.ec
// ISO 13400-2 Alive Check Request (0x0007) and Response (0x0008) supervision and watchdog timer.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "doip.eh"
#include "ec_runtime.h"

#define DOIP_ALIVE_CHECK_PAYLOAD_LEN 2

// Constructs an ISO 13400-2 Alive Check Request frame (8 bytes total)
uint32_t doip_build_alive_check_request(uint8_t* outBuf, uint32_t maxLen)
{
   if(!outBuf || maxLen < DOIP_HEADER_SIZE)
   {
      return 0;
   }

   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_ALIVE_CHECK_REQUEST;
   hdr.payloadLength   = 0;

   if(!doip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   return DOIP_HEADER_SIZE;
}

// Validates and processes an incoming Alive Check Response from a client socket
bool doip_process_alive_check_response(DoipNode* node, uint32_t connId, const uint8_t* payload, uint32_t payloadLen)
{
   if(!node || !payload || payloadLen < DOIP_ALIVE_CHECK_PAYLOAD_LEN)
   {
      return false;
   }

   DoipSession* session = doip_find_session(node, connId);
   if(!session)
   {
      return false;
   }

   uint16_t reportedSa = ((uint16_t)payload[0] << 8) | payload[1];
   if(reportedSa != session->clientLogicalAddress)
   {
      // Logical address does not match active socket registration
      return false;
   }

   // Alive check successfully acknowledged: clear watchdog pending flag
   session->aliveCheckPending = false;
   return true;
}

// Scans active sessions for alive check timeouts or required heartbeat pings
void doip_check_alive_timeouts(DoipNode* node, uint64_t currentMs, void (*onTimeout)(uint32_t connId))
{
   if(!node) return;

   for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
   {
      DoipSession* s = &node->sessions[i];
      if(!s->isActivated) continue;

      if(s->aliveCheckPending)
      {
         // Connection is awaiting response: check for timeout expiration
         if(currentMs >= s->lastActivityMs && (currentMs - s->lastActivityMs) > node->aliveCheckTimeoutMs)
         {
            uint32_t timedOutConn = s->connectionId;
            doip_close_session(node, timedOutConn);
            if(onTimeout)
            {
               onTimeout(timedOutConn);
            }
         }
      }
   }
}
