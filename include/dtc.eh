// include/dtc.eh
// Diagnostic Trouble Code (DTC) debouncing, snapshot freeze-frames, and fault storage.

#ifndef MANIFOLD_DTC_EH
#define MANIFOLD_DTC_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

// Automotive DTC 3-byte representation (e.g. P0100 -> 0x010000)
typedef uint32_t DtcCode;

// Snapshot Freeze Frame captured on fault qualification
typedef struct FreezeFrame
{
   uint64_t timestamp;
   double vehicleSpeedKph;
   double engineRpm;
   double batteryVoltage;
   double coolantTempC;
   uint8_t faultCounter;
} FreezeFrame;

// Monitored DTC Entry
typedef struct DtcEntry
{
   DtcCode code;
   uint8_t statusByte;         // Bitfield as defined in ISO 14229-1
   int16_t debounceCounter;
   int16_t failThreshold;      // Debounce limit to qualify fault
   int16_t passThreshold;      // Debounce limit to heal fault
   FreezeFrame freezeFrame;
   uint8_t occurrenceCount;
   uint8_t agingCounter;
} DtcEntry;

#define MAX_DTC_ENTRIES 64

typedef struct FaultManager
{
   DtcEntry entries[MAX_DTC_ENTRIES];
   uint32_t count;
} FaultManager;

#endif // MANIFOLD_DTC_EH
