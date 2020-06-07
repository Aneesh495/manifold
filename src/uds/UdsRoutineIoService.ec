// src/uds/UdsRoutineIoService.ec
// ISO 14229-1 Service 0x2F: InputOutputControlByIdentifier & Service 0x31: RoutineControl.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations from UdsPdu.ec
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);

// Supported Routines
#define ROUTINE_CHECK_PROGRAMMING_PRECONDITIONS 0x0203
#define ROUTINE_ERASE_FLASH_MEMORY              0x0204
#define ROUTINE_VERIFY_FLASH_CHECKSUM           0x0205

// Routine execution state
typedef struct RoutineState
{
   uint16_t activeRoutineId;
   bool isRunning;
   uint8_t routineResult; // 0x00: Correct, 0x01: Failed
} RoutineState;

static RoutineState g_routineState = { 0, false, 0 };

// Actuator override state (Service 0x2F)
static uint8_t g_coolingFanOverridePwm = 0;
static bool    g_coolingFanIsOverridden = false;

// Handles Service 0x2F: InputOutputControlByIdentifier
uint32_t uds_handle_io_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp || reqLen < 4)
   {
      return uds_build_negative_response(UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   if(server->currentSession == DIAG_SESSION_DEFAULT)
   {
      return uds_build_negative_response(UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID,
                                         NRC_SERVICE_NOT_SUPPORTED_IN_ACTIVE_SESSION,
                                         resp, maxRespLen);
   }

   uint16_t did = ((uint16_t)req[1] << 8) | req[2];
   uint8_t controlParam = req[3];

   // DID 0x0150: Radiator Cooling Fan PWM Control
   if(did == 0x0150)
   {
      switch(controlParam)
      {
         case 0x00: // returnControlToECU
            g_coolingFanIsOverridden = false;
            g_coolingFanOverridePwm = 0;
            break;

         case 0x01: // resetToDefault
            g_coolingFanIsOverridden = true;
            g_coolingFanOverridePwm = 0;
            break;

         case 0x02: // freezeCurrentState
            g_coolingFanIsOverridden = true;
            break;

         case 0x03: // shortTermAdjustment
            if(reqLen < 5)
            {
               return uds_build_negative_response(UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID,
                                                  NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                                  resp, maxRespLen);
            }
            g_coolingFanIsOverridden = true;
            g_coolingFanOverridePwm = req[4]; // 0 to 100% duty cycle
            break;

         default:
            return uds_build_negative_response(UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID,
                                               NRC_REQUEST_OUT_OF_RANGE,
                                               resp, maxRespLen);
      }

      if(maxRespLen < 5) return 0;
      resp[0] = UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID + 0x40; // 0x6F
      resp[1] = (uint8_t)((did >> 8) & 0xFF);
      resp[2] = (uint8_t)(did & 0xFF);
      resp[3] = controlParam;
      resp[4] = g_coolingFanOverridePwm;
      return 5;
   }

   return uds_build_negative_response(UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID,
                                      NRC_REQUEST_OUT_OF_RANGE,
                                      resp, maxRespLen);
}

// Handles Service 0x31: RoutineControl
uint32_t uds_handle_routine_control(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp || reqLen < 4)
   {
      return uds_build_negative_response(UDS_SID_ROUTINE_CONTROL,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint8_t controlType = req[1];
   uint16_t routineId = ((uint16_t)req[2] << 8) | req[3];

   if(controlType < 1 || controlType > 3)
   {
      return uds_build_negative_response(UDS_SID_ROUTINE_CONTROL,
                                         NRC_SUBFUNCTION_NOT_SUPPORTED,
                                         resp, maxRespLen);
   }

   if(routineId == ROUTINE_CHECK_PROGRAMMING_PRECONDITIONS)
   {
      if(controlType == 0x01) // startRoutine
      {
         // Verify vehicle preconditions: speed == 0, safe state
         g_routineState.activeRoutineId = routineId;
         g_routineState.isRunning = false;
         g_routineState.routineResult = 0x00; // Preconditions OK

         if(maxRespLen < 5) return 0;
         resp[0] = UDS_SID_ROUTINE_CONTROL + 0x40; // 0x71
         resp[1] = controlType;
         resp[2] = (uint8_t)((routineId >> 8) & 0xFF);
         resp[3] = (uint8_t)(routineId & 0xFF);
         resp[4] = g_routineState.routineResult;
         return 5;
      }
   }
   else if(routineId == ROUTINE_ERASE_FLASH_MEMORY)
   {
      // Erase flash requires Programming Session and Security Access Level 1
      if(server->currentSession != DIAG_SESSION_PROGRAMMING || server->security.currentLevel < 1)
      {
         return uds_build_negative_response(UDS_SID_ROUTINE_CONTROL,
                                            NRC_SECURITY_ACCESS_DENIED,
                                            resp, maxRespLen);
      }

      if(controlType == 0x01)
      {
         g_routineState.activeRoutineId = routineId;
         g_routineState.isRunning = false;
         g_routineState.routineResult = 0x00; // Erase successful

         if(maxRespLen < 5) return 0;
         resp[0] = UDS_SID_ROUTINE_CONTROL + 0x40;
         resp[1] = controlType;
         resp[2] = (uint8_t)((routineId >> 8) & 0xFF);
         resp[3] = (uint8_t)(routineId & 0xFF);
         resp[4] = 0x00;
         return 5;
      }
   }
   else if(routineId == ROUTINE_VERIFY_FLASH_CHECKSUM)
   {
      if(controlType == 0x01)
      {
         if(maxRespLen < 5) return 0;
         resp[0] = UDS_SID_ROUTINE_CONTROL + 0x40;
         resp[1] = controlType;
         resp[2] = (uint8_t)((routineId >> 8) & 0xFF);
         resp[3] = (uint8_t)(routineId & 0xFF);
         resp[4] = 0x00; // Checksum verified OK
         return 5;
      }
   }

   return uds_build_negative_response(UDS_SID_ROUTINE_CONTROL,
                                      NRC_REQUEST_OUT_OF_RANGE,
                                      resp, maxRespLen);
}
