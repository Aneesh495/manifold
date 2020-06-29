// src/uds/UdsDtcService.ec
// ISO 14229-1 Service 0x19: ReadDTCInformation & Service 0x14: ClearDiagnosticInformation.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "dtc.eh"
#include "ec_runtime.h"

// Forward declarations from UdsPdu.ec, FreezeFrame.ec, and FaultAging.ec
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);
uint32_t freeze_frame_serialize(const FreezeFrame* ff, uint8_t* outBuf, uint32_t maxLen);
uint32_t fault_serialize_extended_data(const DtcEntry* entry, uint8_t recordNumber, uint8_t* outBuf, uint32_t maxLen);

#define DTC_STATUS_AVAILABILITY_MASK 0xFF

// Global fault manager instance shared across UDS diagnostic stack
static FaultManager g_udsFaultManager;

FaultManager* uds_get_fault_manager(void)
{
   return &g_udsFaultManager;
}

// Handles Service 0x19: ReadDTCInformation
uint32_t uds_handle_read_dtc_info(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   (void)server;
   if(!req || !resp || reqLen < 2)
   {
      return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint8_t sub = req[1];

   switch(sub)
   {
      case 0x01: // reportNumberOfDTCByStatusMask
      {
         if(reqLen < 3)
         {
            return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                               NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                               resp, maxRespLen);
         }
         uint8_t mask = req[2];
         uint16_t matchingCount = 0;
         for(uint32_t i = 0; i < g_udsFaultManager.count; i++)
         {
            if((g_udsFaultManager.entries[i].statusByte & mask) != 0)
            {
               matchingCount++;
            }
         }

         if(maxRespLen < 6) return 0;
         resp[0] = UDS_SID_READ_DTC_INFORMATION + 0x40; // 0x59
         resp[1] = sub;
         resp[2] = DTC_STATUS_AVAILABILITY_MASK;
         resp[3] = 0x01; // ISO 14229-1 DTCFormat
         resp[4] = (uint8_t)((matchingCount >> 8) & 0xFF);
         resp[5] = (uint8_t)(matchingCount & 0xFF);
         return 6;
      }

      case 0x02: // reportDTCByStatusMask
      {
         if(reqLen < 3)
         {
            return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                               NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                               resp, maxRespLen);
         }
         uint8_t mask = req[2];

         if(maxRespLen < 3) return 0;
         resp[0] = UDS_SID_READ_DTC_INFORMATION + 0x40; // 0x59
         resp[1] = sub;
         resp[2] = DTC_STATUS_AVAILABILITY_MASK;
         uint32_t pos = 3;

         for(uint32_t i = 0; i < g_udsFaultManager.count; i++)
         {
            DtcEntry* e = &g_udsFaultManager.entries[i];
            if((e->statusByte & mask) != 0)
            {
               if(pos + 4 > maxRespLen) break;
               resp[pos++] = (uint8_t)((e->code >> 16) & 0xFF);
               resp[pos++] = (uint8_t)((e->code >> 8) & 0xFF);
               resp[pos++] = (uint8_t)(e->code & 0xFF);
               resp[pos++] = e->statusByte;
            }
         }
         return pos;
      }

      case 0x04: // reportDTCSnapshotRecordByDTCNumber
      {
         if(reqLen < 6)
         {
            return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                               NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                               resp, maxRespLen);
         }
         DtcCode targetCode = ((uint32_t)req[2] << 16) | ((uint32_t)req[3] << 8) | req[4];
         uint8_t recordNum = req[5];

         for(uint32_t i = 0; i < g_udsFaultManager.count; i++)
         {
            DtcEntry* e = &g_udsFaultManager.entries[i];
            if(e->code == targetCode)
            {
               if(maxRespLen < 7) return 0;
               resp[0] = UDS_SID_READ_DTC_INFORMATION + 0x40;
               resp[1] = sub;
               resp[2] = (uint8_t)((e->code >> 16) & 0xFF);
               resp[3] = (uint8_t)((e->code >> 8) & 0xFF);
               resp[4] = (uint8_t)(e->code & 0xFF);
               resp[5] = e->statusByte;
               resp[6] = recordNum; // e.g. 0x01 or 0xFF
               uint32_t snapLen = freeze_frame_serialize(&e->freezeFrame, resp + 7, maxRespLen - 7);
               return 7 + snapLen;
            }
         }
         return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                            NRC_REQUEST_OUT_OF_RANGE,
                                            resp, maxRespLen);
      }

      case 0x06: // reportDTCExtendedDataRecordByDTCNumber
      {
         if(reqLen < 6)
         {
            return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                               NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                               resp, maxRespLen);
         }
         DtcCode targetCode = ((uint32_t)req[2] << 16) | ((uint32_t)req[3] << 8) | req[4];
         uint8_t recordNum = req[5];

         for(uint32_t i = 0; i < g_udsFaultManager.count; i++)
         {
            DtcEntry* e = &g_udsFaultManager.entries[i];
            if(e->code == targetCode)
            {
               if(maxRespLen < 6) return 0;
               resp[0] = UDS_SID_READ_DTC_INFORMATION + 0x40;
               resp[1] = sub;
               resp[2] = (uint8_t)((e->code >> 16) & 0xFF);
               resp[3] = (uint8_t)((e->code >> 8) & 0xFF);
               resp[4] = (uint8_t)(e->code & 0xFF);
               resp[5] = e->statusByte;
               uint32_t extLen = fault_serialize_extended_data(e, recordNum, resp + 6, maxRespLen - 6);
               return 6 + extLen;
            }
         }
         return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                            NRC_REQUEST_OUT_OF_RANGE,
                                            resp, maxRespLen);
      }

      default:
         return uds_build_negative_response(UDS_SID_READ_DTC_INFORMATION,
                                            NRC_SUBFUNCTION_NOT_SUPPORTED,
                                            resp, maxRespLen);
   }
}

// Handles Service 0x14: ClearDiagnosticInformation
uint32_t uds_handle_clear_dtc_info(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   (void)server;
   if(!req || !resp || reqLen < 4)
   {
      return uds_build_negative_response(UDS_SID_CLEAR_DIAGNOSTIC_INFORMATION,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint32_t group = ((uint32_t)req[1] << 16) | ((uint32_t)req[2] << 8) | req[3];

   // 0xFFFFFF designates All DTCs
   for(uint32_t i = 0; i < g_udsFaultManager.count; i++)
   {
      DtcEntry* e = &g_udsFaultManager.entries[i];
      if(group == 0xFFFFFF || e->code == group)
      {
         e->statusByte = 0x50; // testNotCompletedSinceLastClear | testNotCompletedThisOperationCycle
         e->debounceCounter = 0;
         e->occurrenceCount = 0;
         e->agingCounter = 0;
         memset(&e->freezeFrame, 0, sizeof(FreezeFrame));
      }
   }

   if(maxRespLen < 1) return 0;
   resp[0] = UDS_SID_CLEAR_DIAGNOSTIC_INFORMATION + 0x40; // 0x54
   return 1;
}
