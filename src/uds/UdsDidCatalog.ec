// src/uds/UdsDidCatalog.ec
// Comprehensive ISO 14229-1 / SAE J1979 Data Identifier (DID) catalog and dynamic query engine.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

static const UdsDidDefinition g_didDefinitions[] = {
   // Standard ISO 14229 Identification DIDs
   { 0xF180, "BootSoftwareIdentification", 16, false, 0, 0, "BOOT_V01.00.00_R" },
   { 0xF181, "ApplicationSoftwareIdentification", 16, false, 0, 0, "APP_V02.04.12_REL" },
   { 0xF182, "ApplicationDataIdentification", 16, false, 0, 0, "DATA_CAL_20261108" },
   { 0xF186, "ActiveDiagnosticSessionDataIdentifier", 1, false, 0, 0, "\x01" },
   { 0xF187, "VehicleManufacturerSparePartNumber", 10, false, 0, 0, "8V0907115B" },
   { 0xF188, "VehicleManufacturerECUSoftwareNumber", 10, false, 0, 0, "8V0906259H" },
   { 0xF189, "VehicleManufacturerECUSoftwareVersionNumber", 4, false, 0, 0, "0004" },
   { 0xF190, "VehicleIdentificationNumber (VIN)", 17, false, 0, 1, "1HGBH41JXMN109186" },
   { 0xF191, "VehicleManufacturerECUHardwareNumber", 10, false, 0, 0, "06L907425C" },
   { 0xF192, "SystemSupplierECUHardwareNumber", 10, false, 0, 0, "BOSCH_MED17" },
   { 0xF193, "SystemSupplierECUHardwareVersionNumber", 4, false, 0, 0, "H002" },
   { 0xF194, "SystemSupplierECUSoftwareNumber", 10, false, 0, 0, "1037528341" },
   { 0xF195, "SystemSupplierECUSoftwareVersionNumber", 4, false, 0, 0, "SW08" },
   { 0xF197, "SystemNameOrEngineType", 12, false, 0, 0, "MANIFOLD_CGW" },
   { 0xF198, "RepairShopCodeOrTesterSerialNumber", 10, true, 0, 1, "TESTER_0042" },
   { 0xF199, "ProgrammingDate", 4, true, 0, 1, "\x20\x26\x11\x08" },

   // Operational Live Telemetry DIDs
   { 0x0100, "EngineSpeedRpm", 2, false, 0, 0, "\x0B\xB8" }, // 3000 RPM
   { 0x0101, "VehicleSpeedKph", 2, false, 0, 0, "\x00\x58" }, // 88 km/h
   { 0x0102, "ThrottlePositionPct", 1, false, 0, 0, "\x2D" }, // 45%
   { 0x0103, "EngineCoolantTempDegC", 1, false, 0, 0, "\x82" }, // 90 C (offset -40: raw 130)
   { 0x0104, "FuelTankLevelPct", 1, false, 0, 0, "\x4B" }, // 75%
   { 0x0105, "BatteryVoltageMilliVolts", 2, false, 0, 0, "\x35\x84" }, // 13700 mV (13.7V)
   { 0x0106, "AmbientAirTempDegC", 1, false, 0, 0, "\x3C" }, // 20 C (offset -40: raw 60)
   { 0x0107, "IntakeAirTempDegC", 1, false, 0, 0, "\x46" }, // 30 C
   { 0x0108, "MassAirFlowGramsPerSec", 2, false, 0, 0, "\x00\xE1" }, // 22.5 g/s (scaled x10)
   { 0x0109, "FuelRailPressureKpa", 2, false, 0, 0, "\x4E\x20" }, // 20000 kPa (200 bar)
   { 0x010A, "BarometricPressureKpa", 1, false, 0, 0, "\x65" }, // 101 kPa
   { 0x0110, "SteeringWheelAngleDeg", 2, false, 0, 0, "\x00\x00" }, // 0.0 deg
   { 0x0111, "YawRateDegPerSec", 2, false, 0, 0, "\x00\x00" }, // 0.0 deg/s
   { 0x0112, "MasterCylinderPressureBar", 2, false, 0, 0, "\x00\x00" }, // 0 bar
   { 0x0120, "HighVoltageBatterySocPct", 2, false, 0, 0, "\x21\x34" }, // 85.00%
   { 0x0121, "HighVoltageBatterySohPct", 2, false, 0, 0, "\x26\xAC" }, // 99.00%
   { 0x0122, "HighVoltagePackVoltageVolts", 2, false, 0, 0, "\x0F\xA0" }, // 400.0 V
   { 0x0123, "HighVoltagePackCurrentAmps", 2, false, 0, 0, "\x00\x96" }, // 15.0 A
   { 0x0124, "HighVoltageMaxCellTempDegC", 1, false, 0, 0, "\x32" }, // 28 C
   { 0x0125, "HighVoltageMinCellTempDegC", 1, false, 0, 0, "\x30" }  // 26 C
};

#define UDS_DID_CATALOG_SIZE (sizeof(g_didDefinitions) / sizeof(g_didDefinitions[0]))

// Looks up a DID definition from the catalog
const UdsDidDefinition* uds_did_catalog_lookup(uint16_t did)
{
   for(size_t i = 0; i < UDS_DID_CATALOG_SIZE; i++)
   {
      if(g_didDefinitions[i].did == did)
      {
         return &g_didDefinitions[i];
      }
   }
   return NULL;
}

// Retrieves the standard payload and length for a DID query
bool uds_did_catalog_read(uint16_t did, uint8_t* outBuf, uint32_t* outLen, uint32_t maxLen)
{
   if(!outBuf || !outLen) return false;

   const UdsDidDefinition* def = uds_did_catalog_lookup(did);
   if(!def) return false;

   if(maxLen < def->length) return false;

   memcpy(outBuf, def->defaultPayload, def->length);
   *outLen = def->length;
   return true;
}
