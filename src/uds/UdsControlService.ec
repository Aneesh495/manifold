// src/uds/UdsControlService.ec
// ISO 14229-1 Service 0x11: ECUReset, Service 0x28: CommunicationControl,
// and Service 0x3E: TesterPresent.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations from UdsPdu.ec and UdsSessionService.ec
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);
bool uds_is_suppress_pos_rsp(uint8_t subfunction);
uint8_t uds_get_clean_subfunction(uint8_t subfunction);
void uds_session_init(UdsServer* server);

// Handles Service 0x11: ECUReset
uint32_t uds_handle_ecu_reset(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp) return 0;

   if(reqLen < 2)
   {
      return uds_build_negative_response(UDS_SID_ECU_RESET,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint8_t rawSub = req[1];
   uint8_t resetType = uds_get_clean_subfunction(rawSub);
   bool suppressPos = uds_is_suppress_pos_rsp(rawSub);

   if(resetType < 1 || resetType > 4)
   {
      return uds_build_negative_response(UDS_SID_ECU_RESET,
                                         NRC_SUBFUNCTION_NOT_SUPPORTED,
                                         resp, maxRespLen);
   }

   // Perform reset: reset session state back to default
   uds_session_init(server);

   if(suppressPos) return 0;

   if(maxRespLen < 2) return 0;
   resp[0] = UDS_SID_ECU_RESET + 0x40; // 0x51
   resp[1] = resetType;
   return 2;
}

// Handles Service 0x28: CommunicationControl
uint32_t uds_handle_communication_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp) return 0;

   if(reqLen < 3)
   {
      return uds_build_negative_response(UDS_SID_COMMUNICATION_CONTROL,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   // Only permitted in non-default sessions
   if(server->currentSession == DIAG_SESSION_DEFAULT)
   {
      return uds_build_negative_response(UDS_SID_COMMUNICATION_CONTROL,
                                         NRC_SERVICE_NOT_SUPPORTED_IN_ACTIVE_SESSION,
                                         resp, maxRespLen);
   }

   uint8_t rawSub = req[1];
   uint8_t controlType = uds_get_clean_subfunction(rawSub);
   bool suppressPos = uds_is_suppress_pos_rsp(rawSub);

   if(controlType > 3)
   {
      return uds_build_negative_response(UDS_SID_COMMUNICATION_CONTROL,
                                         NRC_SUBFUNCTION_NOT_SUPPORTED,
                                         resp, maxRespLen);
   }

   uint8_t commType = req[2]; // Communication type (normal, NM, or both)
   if(commType == 0 || commType > 3)
   {
      return uds_build_negative_response(UDS_SID_COMMUNICATION_CONTROL,
                                         NRC_REQUEST_OUT_OF_RANGE,
                                         resp, maxRespLen);
   }

   // Apply communication state
   if(controlType == 0x00) // enableRxAndTx
   {
      server->communicationEnabled = true;
   }
   else if(controlType == 0x03) // disableRxAndTx
   {
      server->communicationEnabled = false;
   }

   if(suppressPos) return 0;

   if(maxRespLen < 2) return 0;
   resp[0] = UDS_SID_COMMUNICATION_CONTROL + 0x40; // 0x68
   resp[1] = controlType;
   return 2;
}

// Handles Service 0x3E: TesterPresent
uint32_t uds_handle_tester_present(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp) return 0;

   if(reqLen < 2)
   {
      return uds_build_negative_response(UDS_SID_TESTER_PRESENT,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint8_t rawSub = req[1];
   uint8_t sub = uds_get_clean_subfunction(rawSub);
   bool suppressPos = uds_is_suppress_pos_rsp(rawSub);

   if(sub != 0x00)
   {
      return uds_build_negative_response(UDS_SID_TESTER_PRESENT,
                                         NRC_SUBFUNCTION_NOT_SUPPORTED,
                                         resp, maxRespLen);
   }

   // Keepalive: reset S3 session timer
   server->lastTesterPresentMs = ec_get_time_ms();

   if(suppressPos) return 0;

   if(maxRespLen < 2) return 0;
   resp[0] = UDS_SID_TESTER_PRESENT + 0x40; // 0x7E
   resp[1] = 0x00;
   return 2;
}
