// src/dtc/FaultAging.ec
// DTC extended data records, occurrence counters, and warm-up cycle aging.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "dtc.eh"
#include "ec_runtime.h"

#define DTC_EXTENDED_DATA_OCCURRENCE_REC  0x01
#define DTC_EXTENDED_DATA_AGING_REC       0x02

// Serializes extended data records for Service 0x19 subfunction 0x06
uint32_t fault_serialize_extended_data(const DtcEntry* entry, uint8_t recordNumber, uint8_t* outBuf, uint32_t maxLen)
{
   if(!entry || !outBuf || maxLen < 4) return 0;

   uint32_t pos = 0;

   if(recordNumber == DTC_EXTENDED_DATA_OCCURRENCE_REC || recordNumber == 0xFF)
   {
      // Record 0x01: Fault Occurrence Counter
      outBuf[pos++] = DTC_EXTENDED_DATA_OCCURRENCE_REC;
      outBuf[pos++] = entry->occurrenceCount;
   }

   if(recordNumber == DTC_EXTENDED_DATA_AGING_REC || recordNumber == 0xFF)
   {
      // Record 0x02: Aging Counter
      if(pos + 2 <= maxLen)
      {
         outBuf[pos++] = DTC_EXTENDED_DATA_AGING_REC;
         outBuf[pos++] = entry->agingCounter;
      }
   }

   return pos;
}
