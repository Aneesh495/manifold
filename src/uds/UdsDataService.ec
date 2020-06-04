// src/uds/UdsDataService.ec
// ISO 14229-1 Service 0x22: ReadDataByIdentifier & Service 0x2E: WriteDataByIdentifier.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations from UdsPdu.ec
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);

// Simulated ECU persistent data storage
static char g_ecuVin[18] = "1HGBH41JXMN109186";
static char g_ecuSerial[17] = "MNFLD-ECU-202601";
static uint8_t g_swVersion[4] = { 1, 0, 0, 42 };

// Dynamic sensor values updated by vehicle simulator
static uint16_t g_sensorSpeedKph = 85;       // 85 km/h
static uint16_t g_sensorRpm = 2450;          // 2450 RPM
static uint16_t g_sensorBatteryCentiVolts = 1380; // 13.80 V
static int8_t   g_sensorCoolantC = 92;       // 92 C
static uint32_t g_sensorOdometerKm = 14205;  // 14,205 km

void uds_sensor_set_values(uint16_t speed, uint16_t rpm, uint16_t batteryCv, int8_t coolant, uint32_t odometer)
{
   g_sensorSpeedKph = speed;
   g_sensorRpm = rpm;
   g_sensorBatteryCentiVolts = batteryCv;
   g_sensorCoolantC = coolant;
   g_sensorOdometerKm = odometer;
}

// Handles Service 0x22: ReadDataByIdentifier
uint32_t uds_handle_read_did(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   (void)server;
   if(!req || !resp || reqLen < 3)
   {
      return uds_build_negative_response(UDS_SID_READ_DATA_BY_IDENTIFIER,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   resp[0] = UDS_SID_READ_DATA_BY_IDENTIFIER + 0x40; // 0x62
   uint32_t respPos = 1;

   // Can process multiple 2-byte DIDs in a single request
   for(uint32_t idx = 1; idx + 1 < reqLen; idx += 2)
   {
      uint16_t did = ((uint16_t)req[idx] << 8) | req[idx + 1];

      if(respPos + 2 >= maxRespLen)
      {
         return uds_build_negative_response(UDS_SID_READ_DATA_BY_IDENTIFIER,
                                            NRC_RESPONSE_TOO_LONG,
                                            resp, maxRespLen);
      }

      resp[respPos++] = (uint8_t)((did >> 8) & 0xFF);
      resp[respPos++] = (uint8_t)(did & 0xFF);

      switch(did)
      {
         case UDS_DID_VIN_NUMBER:
            if(respPos + 17 > maxRespLen) return 0;
            memcpy(resp + respPos, g_ecuVin, 17);
            respPos += 17;
            break;

         case UDS_DID_ECU_SERIAL_NUMBER:
            if(respPos + 16 > maxRespLen) return 0;
            memcpy(resp + respPos, g_ecuSerial, 16);
            respPos += 16;
            break;

         case UDS_DID_APPLICATION_SOFTWARE_ID:
            if(respPos + 4 > maxRespLen) return 0;
            memcpy(resp + respPos, g_swVersion, 4);
            respPos += 4;
            break;

         case UDS_DID_VEHICLE_SPEED:
            if(respPos + 2 > maxRespLen) return 0;
            resp[respPos++] = (uint8_t)((g_sensorSpeedKph >> 8) & 0xFF);
            resp[respPos++] = (uint8_t)(g_sensorSpeedKph & 0xFF);
            break;

         case UDS_DID_ENGINE_RPM:
            if(respPos + 2 > maxRespLen) return 0;
            resp[respPos++] = (uint8_t)((g_sensorRpm >> 8) & 0xFF);
            resp[respPos++] = (uint8_t)(g_sensorRpm & 0xFF);
            break;

         case UDS_DID_BATTERY_VOLTAGE:
            if(respPos + 2 > maxRespLen) return 0;
            resp[respPos++] = (uint8_t)((g_sensorBatteryCentiVolts >> 8) & 0xFF);
            resp[respPos++] = (uint8_t)(g_sensorBatteryCentiVolts & 0xFF);
            break;

         case UDS_DID_COOLANT_TEMPERATURE:
            if(respPos + 1 > maxRespLen) return 0;
            resp[respPos++] = (uint8_t)g_sensorCoolantC;
            break;

         case UDS_DID_ODOMETER:
            if(respPos + 4 > maxRespLen) return 0;
            resp[respPos++] = (uint8_t)((g_sensorOdometerKm >> 24) & 0xFF);
            resp[respPos++] = (uint8_t)((g_sensorOdometerKm >> 16) & 0xFF);
            resp[respPos++] = (uint8_t)((g_sensorOdometerKm >> 8) & 0xFF);
            resp[respPos++] = (uint8_t)(g_sensorOdometerKm & 0xFF);
            break;

         default:
            return uds_build_negative_response(UDS_SID_READ_DATA_BY_IDENTIFIER,
                                               NRC_REQUEST_OUT_OF_RANGE,
                                               resp, maxRespLen);
      }
   }

   return respPos;
}

// Handles Service 0x2E: WriteDataByIdentifier
uint32_t uds_handle_write_did(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp || reqLen < 4)
   {
      return uds_build_negative_response(UDS_SID_WRITE_DATA_BY_IDENTIFIER,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   // Writing requires non-default session
   if(server->currentSession == DIAG_SESSION_DEFAULT)
   {
      return uds_build_negative_response(UDS_SID_WRITE_DATA_BY_IDENTIFIER,
                                         NRC_SERVICE_NOT_SUPPORTED_IN_ACTIVE_SESSION,
                                         resp, maxRespLen);
   }

   uint16_t did = ((uint16_t)req[1] << 8) | req[2];
   const uint8_t* data = req + 3;
   uint32_t dataLen = reqLen - 3;

   switch(did)
   {
      case UDS_DID_VIN_NUMBER:
      {
         // Writing VIN requires Security Access Level 1 or higher
         if(server->security.currentLevel < 1)
         {
            return uds_build_negative_response(UDS_SID_WRITE_DATA_BY_IDENTIFIER,
                                               NRC_SECURITY_ACCESS_DENIED,
                                               resp, maxRespLen);
         }
         if(dataLen != 17)
         {
            return uds_build_negative_response(UDS_SID_WRITE_DATA_BY_IDENTIFIER,
                                               NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                               resp, maxRespLen);
         }
         memcpy(g_ecuVin, data, 17);
         g_ecuVin[17] = '\0';
         break;
      }

      default:
         return uds_build_negative_response(UDS_SID_WRITE_DATA_BY_IDENTIFIER,
                                            NRC_REQUEST_OUT_OF_RANGE,
                                            resp, maxRespLen);
   }

   if(maxRespLen < 3) return 0;
   resp[0] = UDS_SID_WRITE_DATA_BY_IDENTIFIER + 0x40; // 0x6E
   resp[1] = (uint8_t)((did >> 8) & 0xFF);
   resp[2] = (uint8_t)(did & 0xFF);
   return 3;
}
