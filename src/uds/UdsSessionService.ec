// src/uds/UdsSessionService.ec
// ISO 14229-1 Service 0x10: DiagnosticSessionControl & S3 session timeout supervision.

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

#define UDS_P2_SERVER_MAX_MS       50    // 50 ms standard response
#define UDS_P2_STAR_SERVER_MAX_RES 500   // 5000 ms / 10 ms units = 500
#define UDS_S3_SERVER_TIMEOUT_MS   5000  // 5 seconds session timeout

void uds_session_init(UdsServer* server)
{
   if(!server) return;
   server->currentSession = DIAG_SESSION_DEFAULT;
   server->security.currentLevel = 0; // Locked
   server->security.seedGenerated = false;
   server->communicationEnabled = true;
   server->lastTesterPresentMs = ec_get_time_ms();
   server->transferActive = false;
}

// Handles Service 0x10 DiagnosticSessionControl
uint32_t uds_handle_session_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp) return 0;

   if(reqLen < 2)
   {
      return uds_build_negative_response(UDS_SID_DIAGNOSTIC_SESSION_CONTROL,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint8_t rawSub = req[1];
   uint8_t sub = uds_get_clean_subfunction(rawSub);
   bool suppressPos = uds_is_suppress_pos_rsp(rawSub);

   switch(sub)
   {
      case DIAG_SESSION_DEFAULT:
      case DIAG_SESSION_PROGRAMMING:
      case DIAG_SESSION_EXTENDED:
      case DIAG_SESSION_SAFETY_SYSTEM:
         break;
      default:
         return uds_build_negative_response(UDS_SID_DIAGNOSTIC_SESSION_CONTROL,
                                            NRC_SUBFUNCTION_NOT_SUPPORTED,
                                            resp, maxRespLen);
   }

   // Session transition
   server->currentSession = (DiagnosticSessionType)sub;
   server->lastTesterPresentMs = ec_get_time_ms();

   // Transitioning sessions locks security access per ISO 14229-1
   if(sub == DIAG_SESSION_DEFAULT)
   {
      server->security.currentLevel = 0;
   }

   if(suppressPos)
   {
      return 0; // Positive response suppressed
   }

   if(maxRespLen < 6) return 0;
   resp[0] = UDS_SID_DIAGNOSTIC_SESSION_CONTROL + 0x40; // 0x50
   resp[1] = sub;
   // P2Server_max (MSB, LSB) in milliseconds
   resp[2] = (uint8_t)((UDS_P2_SERVER_MAX_MS >> 8) & 0xFF);
   resp[3] = (uint8_t)(UDS_P2_SERVER_MAX_MS & 0xFF);
   // P2*Server_max in 10-millisecond resolution
   resp[4] = (uint8_t)((UDS_P2_STAR_SERVER_MAX_RES >> 8) & 0xFF);
   resp[5] = (uint8_t)(UDS_P2_STAR_SERVER_MAX_RES & 0xFF);
   return 6;
}

// S3 server timer supervision: checks if active session timed out due to missing TesterPresent
void uds_session_check_timeout(UdsServer* server, uint64_t currentMs)
{
   if(!server) return;

   if(server->currentSession != DIAG_SESSION_DEFAULT)
   {
      if(currentMs - server->lastTesterPresentMs >= UDS_S3_SERVER_TIMEOUT_MS)
      {
         // Session timed out, revert to default session and lock security
         server->currentSession = DIAG_SESSION_DEFAULT;
         server->security.currentLevel = 0;
         server->transferActive = false;
      }
   }
}
