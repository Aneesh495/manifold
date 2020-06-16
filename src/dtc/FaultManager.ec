// src/dtc/FaultManager.ec
// ISO 14229-1 DTC status byte state machine, counter-based debouncing, and fault qualification.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "dtc.eh"
#include "ec_runtime.h"

#define DTC_STATUS_TEST_FAILED                      0x01
#define DTC_STATUS_TEST_FAILED_THIS_CYCLE           0x02
#define DTC_STATUS_PENDING                          0x04
#define DTC_STATUS_CONFIRMED                        0x08
#define DTC_STATUS_NOT_COMPLETED_SINCE_CLEAR        0x10
#define DTC_STATUS_FAILED_SINCE_CLEAR               0x20
#define DTC_STATUS_NOT_COMPLETED_THIS_CYCLE         0x40
#define DTC_STATUS_WARNING_INDICATOR_REQUESTED      0x80

// Forward declaration from FreezeFrame.ec
void freeze_frame_capture(FreezeFrame* ff, uint8_t faultCount);

void fault_manager_init(FaultManager* mgr)
{
   if(!mgr) return;
   memset(mgr, 0, sizeof(FaultManager));
}

DtcEntry* fault_manager_add_dtc(FaultManager* mgr, DtcCode code, int16_t failThreshold, int16_t passThreshold)
{
   if(!mgr || mgr->count >= MAX_DTC_ENTRIES) return NULL;

   DtcEntry* entry = &mgr->entries[mgr->count++];
   memset(entry, 0, sizeof(DtcEntry));
   entry->code = code;
   entry->failThreshold = failThreshold;
   entry->passThreshold = passThreshold;
   entry->statusByte = DTC_STATUS_NOT_COMPLETED_SINCE_CLEAR | DTC_STATUS_NOT_COMPLETED_THIS_CYCLE;
   return entry;
}

DtcEntry* fault_manager_find_dtc(FaultManager* mgr, DtcCode code)
{
   if(!mgr) return NULL;
   for(uint32_t i = 0; i < mgr->count; i++)
   {
      if(mgr->entries[i].code == code) return &mgr->entries[i];
   }
   return NULL;
}

// Debounce evaluation step: testFailed = true if pre-failed, false if pre-passed
bool fault_manager_report_test_result(FaultManager* mgr, DtcCode code, bool isFailed)
{
   DtcEntry* entry = fault_manager_find_dtc(mgr, code);
   if(!entry) return false;

   // Test is now completed for this cycle and since clear
   entry->statusByte &= ~DTC_STATUS_NOT_COMPLETED_THIS_CYCLE;
   entry->statusByte &= ~DTC_STATUS_NOT_COMPLETED_SINCE_CLEAR;

   if(isFailed)
   {
      if(entry->debounceCounter < entry->failThreshold)
      {
         entry->debounceCounter += 10;
      }

      if(entry->debounceCounter >= entry->failThreshold)
      {
         // Fault Qualified
         entry->statusByte |= DTC_STATUS_TEST_FAILED;
         entry->statusByte |= DTC_STATUS_TEST_FAILED_THIS_CYCLE;
         entry->statusByte |= DTC_STATUS_PENDING;
         entry->statusByte |= DTC_STATUS_FAILED_SINCE_CLEAR;

         if(!(entry->statusByte & DTC_STATUS_CONFIRMED))
         {
            entry->statusByte |= DTC_STATUS_CONFIRMED;
            entry->statusByte |= DTC_STATUS_WARNING_INDICATOR_REQUESTED;
            entry->occurrenceCount++;

            // Capture Snapshot Record (Freeze Frame)
            freeze_frame_capture(&entry->freezeFrame, entry->occurrenceCount);
         }
      }
   }
   else
   {
      // Test passed
      if(entry->debounceCounter > entry->passThreshold)
      {
         entry->debounceCounter -= 5;
      }

      if(entry->debounceCounter <= entry->passThreshold)
      {
         // Fault Healed for current test
         entry->statusByte &= ~DTC_STATUS_TEST_FAILED;
      }
   }

   return true;
}

// Operation cycle transition (e.g. Ignition Off -> Ignition On)
void fault_manager_start_operation_cycle(FaultManager* mgr)
{
   if(!mgr) return;

   for(uint32_t i = 0; i < mgr->count; i++)
   {
      DtcEntry* entry = &mgr->entries[i];
      entry->statusByte &= ~DTC_STATUS_TEST_FAILED_THIS_CYCLE;
      entry->statusByte |= DTC_STATUS_NOT_COMPLETED_THIS_CYCLE;
      entry->debounceCounter = 0; // Reset debouncer for new cycle

      // If test passes in this cycle and confirmed, aging counter increments
      if((entry->statusByte & DTC_STATUS_CONFIRMED) && !(entry->statusByte & DTC_STATUS_TEST_FAILED))
      {
         entry->agingCounter++;
         if(entry->agingCounter >= 40) // 40 consecutive healing warm-up cycles clears confirmed fault
         {
            entry->statusByte &= ~DTC_STATUS_CONFIRMED;
            entry->statusByte &= ~DTC_STATUS_PENDING;
            entry->statusByte &= ~DTC_STATUS_WARNING_INDICATOR_REQUESTED;
         }
      }
   }
}
