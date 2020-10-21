// src/dtc/DtcCatalog.ec
// Comprehensive SAE J2012 / ISO 14229 Diagnostic Trouble Code (DTC) catalog and symptom database.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "dtc.eh"
#include "ec_runtime.h"

typedef struct DtcCatalogEntry
{
   uint32_t code;
   const char* codeStr;
   const char* description;
   const char* system;
   int8_t failStep;
   int8_t passStep;
} DtcCatalogEntry;

static const DtcCatalogEntry g_dtcCatalog[] = {
   // Powertrain (P-codes)
   { 0x010000, "P0100", "Mass or Volume Air Flow Circuit Malfunction", "Powertrain", 20, -10 },
   { 0x010100, "P0101", "Mass or Volume Air Flow Circuit Range/Performance Problem", "Powertrain", 20, -10 },
   { 0x010200, "P0102", "Mass or Volume Air Flow Circuit Low Input", "Powertrain", 15, -10 },
   { 0x010300, "P0103", "Mass or Volume Air Flow Circuit High Input", "Powertrain", 15, -10 },
   { 0x010500, "P0105", "Manifold Absolute Pressure/Barometric Pressure Circuit Malfunction", "Powertrain", 20, -10 },
   { 0x010600, "P0106", "Manifold Absolute Pressure/Barometric Pressure Circuit Range/Performance", "Powertrain", 25, -10 },
   { 0x011000, "P0110", "Intake Air Temperature Circuit Malfunction", "Powertrain", 20, -10 },
   { 0x011500, "P0115", "Engine Coolant Temperature Circuit Malfunction", "Powertrain", 30, -10 },
   { 0x011600, "P0116", "Engine Coolant Temperature Circuit Range/Performance Problem", "Powertrain", 30, -10 },
   { 0x011700, "P0117", "Engine Coolant Temperature Circuit Low Input", "Powertrain", 20, -10 },
   { 0x011800, "P0118", "Engine Coolant Temperature Circuit High Input", "Powertrain", 20, -10 },
   { 0x012000, "P0120", "Throttle/Pedal Position Sensor/Switch A Circuit Malfunction", "Powertrain", 10, -5 },
   { 0x012100, "P0121", "Throttle/Pedal Position Sensor/Switch A Circuit Range/Performance", "Powertrain", 15, -10 },
   { 0x013000, "P0130", "O2 Sensor Circuit Malfunction (Bank 1 Sensor 1)", "Powertrain", 25, -10 },
   { 0x013100, "P0131", "O2 Sensor Circuit Low Voltage (Bank 1 Sensor 1)", "Powertrain", 20, -10 },
   { 0x013200, "P0132", "O2 Sensor Circuit High Voltage (Bank 1 Sensor 1)", "Powertrain", 20, -10 },
   { 0x013300, "P0133", "O2 Sensor Circuit Slow Response (Bank 1 Sensor 1)", "Powertrain", 40, -10 },
   { 0x017100, "P0171", "System Too Lean (Bank 1)", "Powertrain", 50, -20 },
   { 0x017200, "P0172", "System Too Rich (Bank 1)", "Powertrain", 50, -20 },
   { 0x020000, "P0200", "Injector Circuit Malfunction", "Powertrain", 10, -5 },
   { 0x020100, "P0201", "Injector Circuit Malfunction - Cylinder 1", "Powertrain", 10, -5 },
   { 0x020200, "P0202", "Injector Circuit Malfunction - Cylinder 2", "Powertrain", 10, -5 },
   { 0x020300, "P0203", "Injector Circuit Malfunction - Cylinder 3", "Powertrain", 10, -5 },
   { 0x020400, "P0204", "Injector Circuit Malfunction - Cylinder 4", "Powertrain", 10, -5 },
   { 0x030000, "P0300", "Random/Multiple Cylinder Misfire Detected", "Powertrain", 15, -5 },
   { 0x030100, "P0301", "Cylinder 1 Misfire Detected", "Powertrain", 15, -5 },
   { 0x030200, "P0302", "Cylinder 2 Misfire Detected", "Powertrain", 15, -5 },
   { 0x030300, "P0303", "Cylinder 3 Misfire Detected", "Powertrain", 15, -5 },
   { 0x030400, "P0304", "Cylinder 4 Misfire Detected", "Powertrain", 15, -5 },
   { 0x032500, "P0325", "Knock Sensor 1 Circuit Malfunction (Bank 1 or Single Sensor)", "Powertrain", 20, -10 },
   { 0x033500, "P0335", "Crankshaft Position Sensor A Circuit Malfunction", "Powertrain", 10, -5 },
   { 0x034000, "P0340", "Camshaft Position Sensor Circuit Malfunction", "Powertrain", 15, -5 },
   { 0x042000, "P0420", "Catalyst System Efficiency Below Threshold (Bank 1)", "Powertrain", 80, -20 },
   { 0x050000, "P0500", "Vehicle Speed Sensor Malfunction", "Powertrain", 20, -10 },
   { 0x050500, "P0505", "Idle Air Control System Malfunction", "Powertrain", 30, -10 },
   { 0x056200, "P0562", "System Voltage Low", "Powertrain", 20, -10 },
   { 0x056300, "P0563", "System Voltage High", "Powertrain", 20, -10 },
   { 0x060000, "P0600", "Serial Communication Link Malfunction", "Powertrain", 10, -5 },
   { 0x060600, "P0606", "PCM Processor Fault", "Powertrain", 5, -2 },
   { 0x070000, "P0700", "Transmission Control System Malfunction", "Powertrain", 10, -5 },

   // Chassis (C-codes)
   { 0x400100, "C0031", "Left Front Wheel Speed Sensor Malfunction", "Chassis", 10, -5 },
   { 0x400200, "C0034", "Right Front Wheel Speed Sensor Malfunction", "Chassis", 10, -5 },
   { 0x400300, "C0037", "Left Rear Wheel Speed Sensor Malfunction", "Chassis", 10, -5 },
   { 0x400400, "C0040", "Right Rear Wheel Speed Sensor Malfunction", "Chassis", 10, -5 },
   { 0x401000, "C0110", "Pump Motor Circuit Malfunction", "Chassis", 15, -5 },
   { 0x402000, "C0131", "ABS Pressure Transducer Circuit Malfunction", "Chassis", 10, -5 },
   { 0x403000, "C0186", "Lateral Accelerometer Circuit Malfunction", "Chassis", 15, -5 },
   { 0x403500, "C0196", "Yaw Rate Sensor Circuit Malfunction", "Chassis", 15, -5 },
   { 0x404000, "C0245", "Wheel Speed Sensor Frequency Error", "Chassis", 10, -5 },
   { 0x405000, "C0550", "Electronic Control Unit Malfunction (ESC)", "Chassis", 5, -2 },

   // Body (B-codes)
   { 0x800100, "B0001", "Driver Frontal Airbag Stage 1 Deployment Control", "Body", 5, -2 },
   { 0x800200, "B0002", "Driver Frontal Airbag Stage 2 Deployment Control", "Body", 5, -2 },
   { 0x801000, "B0010", "Passenger Frontal Airbag Stage 1 Deployment Control", "Body", 5, -2 },
   { 0x802800, "B0028", "Right Side Airbag Deployment Control", "Body", 5, -2 },
   { 0x805000, "B0050", "Driver Seat Belt Sensor Circuit Malfunction", "Body", 15, -5 },
   { 0x809000, "B0090", "Left Front Restraints Sensor Malfunction", "Body", 10, -5 },
   { 0x900000, "B1000", "Electronic Control Unit Performance (BCM)", "Body", 5, -2 },
   { 0x900400, "B1004", "Keep Alive Memory (KAM) Error", "Body", 5, -2 },
   { 0x901100, "B1011", "Ignition Switch Run/Start Circuit Malfunction", "Body", 10, -5 },

   // Network Communication (U-codes)
   { 0xC00000, "U0001", "High Speed CAN Communication Bus Malfunction", "Network", 5, -2 },
   { 0xC00200, "U0002", "High Speed CAN Communication Bus Performance", "Network", 10, -5 },
   { 0xC00300, "U0003", "High Speed CAN Communication Bus (+) Open", "Network", 5, -2 },
   { 0xC00400, "U0004", "High Speed CAN Communication Bus (+) Low", "Network", 5, -2 },
   { 0xC00500, "U0005", "High Speed CAN Communication Bus (+) High", "Network", 5, -2 },
   { 0xC00600, "U0006", "High Speed CAN Communication Bus (-) Open", "Network", 5, -2 },
   { 0xC00700, "U0007", "High Speed CAN Communication Bus (-) Low", "Network", 5, -2 },
   { 0xC00800, "U0008", "High Speed CAN Communication Bus (-) High", "Network", 5, -2 },
   { 0xC00900, "U0009", "High Speed CAN Communication Bus (-) Shorted to Bus (+)", "Network", 5, -2 },
   { 0xC01000, "U0010", "Medium Speed CAN Communication Bus Malfunction", "Network", 10, -5 },
   { 0xC02000, "U0020", "Low Speed CAN Communication Bus Malfunction", "Network", 15, -5 },
   { 0xC10000, "U0100", "Lost Communication With ECM/PCM 'A'", "Network", 10, -5 },
   { 0xC10100, "U0101", "Lost Communication With TCM", "Network", 10, -5 },
   { 0xC10200, "U0102", "Lost Communication With Transfer Case Control Module", "Network", 15, -5 },
   { 0xC10300, "U0103", "Lost Communication With Gear Shift Module", "Network", 10, -5 },
   { 0xC12100, "U0121", "Lost Communication With Anti-Lock Brake System (ABS) Control Module", "Network", 10, -5 },
   { 0xC12200, "U0122", "Lost Communication With Vehicle Dynamics Control Module (ESC)", "Network", 10, -5 },
   { 0xC12600, "U0126", "Lost Communication With Steering Angle Sensor Module", "Network", 10, -5 },
   { 0xC14000, "U0140", "Lost Communication With Body Control Module (BCM)", "Network", 10, -5 },
   { 0xC15100, "U0151", "Lost Communication With Restraints Control Module (RCM)", "Network", 10, -5 },
   { 0xC15500, "U0155", "Lost Communication With Instrument Panel Cluster (IPC)", "Network", 15, -5 },
   { 0xC16400, "U0164", "Lost Communication With HVAC Control Module", "Network", 20, -10 },
   { 0xC20000, "U0200", "Lost Communication With Door Control Module B", "Network", 20, -10 },
   { 0xC30000, "U0300", "Internal Control Module Software Incompatibility", "Network", 5, -2 },
   { 0xC40000, "U0400", "Invalid Data Received", "Network", 15, -5 },
   { 0xC40100, "U0401", "Invalid Data Received From ECM/PCM", "Network", 15, -5 },
   { 0xC40200, "U0402", "Invalid Data Received From TCM", "Network", 15, -5 },
   { 0xC41500, "U0415", "Invalid Data Received From Anti-Lock Brake System Control Module", "Network", 15, -5 },
   { 0xC41800, "U0418", "Invalid Data Received From Brake System Control Module", "Network", 15, -5 },
   { 0xC42200, "U0422", "Invalid Data Received From Body Control Module", "Network", 15, -5 },
   { 0xC42300, "U0423", "Invalid Data Received From Instrument Panel Cluster Control Module", "Network", 20, -10 }
};

#define DTC_CATALOG_SIZE (sizeof(g_dtcCatalog) / sizeof(g_dtcCatalog[0]))

// Looks up the diagnostic description for a 3-byte DTC code
const char* dtc_catalog_lookup_description(uint32_t code)
{
   for(size_t i = 0; i < DTC_CATALOG_SIZE; i++)
   {
      if(g_dtcCatalog[i].code == code)
      {
         return g_dtcCatalog[i].description;
      }
   }
   return "Unknown Diagnostic Trouble Code";
}

// Populates the active FaultManager instance with standard catalog entries
void dtc_catalog_populate_manager(FaultManager* mgr)
{
   if(!mgr) return;

   for(size_t i = 0; i < DTC_CATALOG_SIZE; i++)
   {
      fault_manager_add_dtc(mgr, g_dtcCatalog[i].code, g_dtcCatalog[i].failStep, g_dtcCatalog[i].passStep);
   }
}
