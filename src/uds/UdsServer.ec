// src/uds/UdsServer.ec
// Master ISO 14229-1 Unified Diagnostic Services request dispatcher and server engine.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations from Uds services
void uds_session_init(UdsServer* server);
void uds_session_check_timeout(UdsServer* server, uint64_t currentMs);
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);

uint32_t uds_handle_session_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_ecu_reset(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_communication_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_tester_present(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_security_access(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_read_did(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_write_did(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_io_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_routine_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_request_download(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_transfer_data(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_transfer_exit(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);

// Forward declarations from DTC service (Milestone 5)
uint32_t uds_handle_read_dtc_info(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t uds_handle_clear_dtc_info(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen);

void uds_server_init(UdsServer* server)
{
   if(!server) return;
   memset(server, 0, sizeof(UdsServer));
   uds_session_init(server);
}

// Master request dispatcher
void uds_server_process_request(UdsServer* server, const uint8_t* req, uint32_t reqLen,
                                uint8_t* resp, uint32_t* respLen)
{
   if(!server || !resp || !respLen) return;
   *respLen = 0;

   if(!req || reqLen == 0)
   {
      *respLen = uds_build_negative_response(0x00, NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT, resp, UDS_MAX_PAYLOAD_SIZE);
      return;
   }

   // Supervise S3 session timer
   uds_session_check_timeout(server, ec_get_time_ms());

   uint8_t sid = req[0];
   uint32_t outLen = 0;

   switch(sid)
   {
      case UDS_SID_DIAGNOSTIC_SESSION_CONTROL:
         outLen = uds_handle_session_control(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_ECU_RESET:
         outLen = uds_handle_ecu_reset(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_COMMUNICATION_CONTROL:
         outLen = uds_handle_communication_control(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_TESTER_PRESENT:
         outLen = uds_handle_tester_present(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_SECURITY_ACCESS:
         outLen = uds_handle_security_access(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_READ_DATA_BY_IDENTIFIER:
         outLen = uds_handle_read_did(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_WRITE_DATA_BY_IDENTIFIER:
         outLen = uds_handle_write_did(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID:
         outLen = uds_handle_io_control(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_ROUTINE_CONTROL:
         outLen = uds_handle_routine_control(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_REQUEST_DOWNLOAD:
         outLen = uds_handle_request_download(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_TRANSFER_DATA:
         outLen = uds_handle_transfer_data(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_REQUEST_TRANSFER_EXIT:
         outLen = uds_handle_transfer_exit(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_READ_DTC_INFORMATION:
         outLen = uds_handle_read_dtc_info(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      case UDS_SID_CLEAR_DIAGNOSTIC_INFORMATION:
         outLen = uds_handle_clear_dtc_info(server, req, reqLen, resp, UDS_MAX_PAYLOAD_SIZE);
         break;

      default:
         outLen = uds_build_negative_response(sid, NRC_SERVICE_NOT_SUPPORTED, resp, UDS_MAX_PAYLOAD_SIZE);
         break;
   }

   *respLen = outLen;
}
