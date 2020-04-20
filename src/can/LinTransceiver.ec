// src/can/LinTransceiver.ec
// LIN 2.2 Local Interconnect Network master scheduler, PID parity, and checksum engine.
// Implements ISO 17987 / LIN 2.2A protocol requirements.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "ec_runtime.h"

#define LIN_MAX_DATA_BYTES 8
#define LIN_MAX_SCHEDULE_ENTRIES 32

typedef struct LinFrame
{
   uint8_t frameId;      // 6-bit ID (0 to 63)
   uint8_t protectedId;  // 8-bit PID with parity P0, P1
   uint8_t length;       // 1 to 8 bytes
   uint8_t data[LIN_MAX_DATA_BYTES];
   uint8_t checksum;
   bool isEnhancedChecksum;
} LinFrame;

typedef struct LinScheduleEntry
{
   uint8_t frameId;
   uint32_t slotDurationMs;
} LinScheduleEntry;

typedef struct LinMasterScheduler
{
   uint32_t channelId;
   LinScheduleEntry schedule[LIN_MAX_SCHEDULE_ENTRIES];
   uint32_t scheduleCount;
   uint32_t currentSlotIndex;
   uint64_t lastSlotAdvanceMs;
   uint64_t totalFramesSent;
   uint64_t checksumErrors;
} LinMasterScheduler;

// Calculates 8-bit Protected Identifier (PID) with P0 and P1 parity bits
uint8_t lin_compute_pid(uint8_t frameId)
{
   uint8_t id = frameId & 0x3F; // 6-bit ID
   uint8_t id0 = (id >> 0) & 1;
   uint8_t id1 = (id >> 1) & 1;
   uint8_t id2 = (id >> 2) & 1;
   uint8_t id3 = (id >> 3) & 1;
   uint8_t id4 = (id >> 4) & 1;
   uint8_t id5 = (id >> 5) & 1;

   uint8_t p0 = id0 ^ id1 ^ id2 ^ id4;
   uint8_t p1 = !(id1 ^ id3 ^ id4 ^ id5);

   return (uint8_t)(id | (p0 << 6) | (p1 << 7));
}

// Verifies whether received PID has valid parity
bool lin_verify_pid(uint8_t pid)
{
   uint8_t expected = lin_compute_pid(pid & 0x3F);
   return (expected == pid);
}

// Computes LIN inverted modulo-256 checksum with carry addition
uint8_t lin_compute_checksum(uint8_t pid, const uint8_t* data, uint8_t length, bool isEnhanced)
{
   if(!data || length == 0) return 0;

   uint16_t sum = 0;
   if(isEnhanced)
   {
      // Enhanced checksum includes PID (diagnostic frames 0x3C and 0x3D always use classic)
      sum += pid;
   }

   for(uint8_t i = 0; i < length; i++)
   {
      sum += data[i];
      if(sum > 0xFF)
      {
         sum = (sum & 0xFF) + 1; // Add carry bit
      }
   }

   return (uint8_t)(~sum & 0xFF);
}

void lin_scheduler_init(LinMasterScheduler* sched, uint32_t channelId)
{
   if(!sched) return;
   memset(sched, 0, sizeof(LinMasterScheduler));
   sched->channelId = channelId;
}

bool lin_scheduler_add_slot(LinMasterScheduler* sched, uint8_t frameId, uint32_t slotDurationMs)
{
   if(!sched || sched->scheduleCount >= LIN_MAX_SCHEDULE_ENTRIES) return false;

   sched->schedule[sched->scheduleCount].frameId = frameId & 0x3F;
   sched->schedule[sched->scheduleCount].slotDurationMs = (slotDurationMs > 0) ? slotDurationMs : 10;
   sched->scheduleCount++;
   return true;
}

// Evaluates scheduler tick and returns whether slot advanced to next frame
bool lin_scheduler_tick(LinMasterScheduler* sched, uint64_t currentMs, uint8_t* outFrameId)
{
   if(!sched || sched->scheduleCount == 0) return false;

   if(currentMs - sched->lastSlotAdvanceMs >= sched->schedule[sched->currentSlotIndex].slotDurationMs)
   {
      if(outFrameId)
      {
         *outFrameId = sched->schedule[sched->currentSlotIndex].frameId;
      }
      sched->currentSlotIndex = (sched->currentSlotIndex + 1) % sched->scheduleCount;
      sched->lastSlotAdvanceMs = currentMs;
      sched->totalFramesSent++;
      return true;
   }
   return false;
}
