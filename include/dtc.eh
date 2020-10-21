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

void fault_manager_init(FaultManager* mgr);
DtcEntry* fault_manager_add_dtc(FaultManager* mgr, DtcCode code, int16_t failThreshold, int16_t passThreshold);
DtcEntry* fault_manager_find_dtc(FaultManager* mgr, DtcCode code);
bool fault_manager_report_test_result(FaultManager* mgr, DtcCode code, bool isFailed);
void fault_manager_start_operation_cycle(FaultManager* mgr);

const char* dtc_catalog_lookup_description(uint32_t code);
void dtc_catalog_populate_manager(FaultManager* mgr);

#endif // MANIFOLD_DTC_EH
