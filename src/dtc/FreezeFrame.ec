// src/dtc/FreezeFrame.ec
// Snapshot record (freeze frame) capture and serialization for ISO 14229-1 Service 0x19.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "dtc.eh"
#include "ec_runtime.h"

// Simulated current vehicle telemetry
static double g_telemetrySpeed = 72.5;       // km/h
static double g_telemetryRpm = 2150.0;       // RPM
static double g_telemetryBattery = 13.95;    // Volts
static double g_telemetryCoolant = 89.0;     // Celsius

void freeze_frame_set_telemetry(double speed, double rpm, double battery, double coolant)
{
   g_telemetrySpeed = speed;
   g_telemetryRpm = rpm;
   g_telemetryBattery = battery;
   g_telemetryCoolant = coolant;
}

// Captures a freeze frame snapshot at the moment of fault qualification
void freeze_frame_capture(FreezeFrame* ff, uint8_t faultCount)
{
   if(!ff) return;

   ff->timestamp = ec_get_time_us();
   ff->vehicleSpeedKph = g_telemetrySpeed;
   ff->engineRpm = g_telemetryRpm;
   ff->batteryVoltage = g_telemetryBattery;
   ff->coolantTempC = g_telemetryCoolant;
   ff->faultCounter = faultCount;
}

// Serializes snapshot record according to ISO 14229-1 Table 28 format
uint32_t freeze_frame_serialize(const FreezeFrame* ff, uint8_t* outBuf, uint32_t maxLen)
{
   if(!ff || !outBuf || maxLen < 15) return 0;

   uint32_t pos = 0;

   // DID 0x0100: Vehicle Speed (2 bytes, 1 km/h per bit)
   outBuf[pos++] = 0x01;
   outBuf[pos++] = 0x00;
   uint16_t spd = (uint16_t)ff->vehicleSpeedKph;
   outBuf[pos++] = (uint8_t)((spd >> 8) & 0xFF);
   outBuf[pos++] = (uint8_t)(spd & 0xFF);

   // DID 0x0101: Engine RPM (2 bytes, 1 RPM per bit)
   outBuf[pos++] = 0x01;
   outBuf[pos++] = 0x01;
   uint16_t rpm = (uint16_t)ff->engineRpm;
   outBuf[pos++] = (uint8_t)((rpm >> 8) & 0xFF);
   outBuf[pos++] = (uint8_t)(rpm & 0xFF);

   // DID 0x0102: Battery Voltage (2 bytes, 0.01 V per bit)
   outBuf[pos++] = 0x01;
   outBuf[pos++] = 0x02;
   uint16_t bat = (uint16_t)(ff->batteryVoltage * 100.0);
   outBuf[pos++] = (uint8_t)((bat >> 8) & 0xFF);
   outBuf[pos++] = (uint8_t)(bat & 0xFF);

   // DID 0x0103: Coolant Temperature (1 byte, 1 C per bit with 40 C offset)
   outBuf[pos++] = 0x01;
   outBuf[pos++] = 0x03;
   outBuf[pos++] = (uint8_t)((int)ff->coolantTempC + 40);

   return pos;
}
