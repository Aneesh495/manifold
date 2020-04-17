// src/can/CanTransceiver.ec
// Virtual CAN bus transceiver with priority arbitration and ring-buffered loopback.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#include "types.eh"
#include "core.eh"
#include "can.eh"
#include "ec_runtime.h"

#define TRANSCEIVER_DEFAULT_QUEUE_SIZE 1024
#define MAX_SUBSCRIBERS_PER_BUS 8

typedef struct CanTransceiver
{
   uint32_t busId;
   char busName[32];
   RingBuffer* txQueue;
   RingBuffer* rxQueue;
   bool isLoopbackEnabled;
   uint64_t totalFramesBroadcast;
   uint64_t totalFramesReceived;
   uint64_t arbitrationLossCount;
} CanTransceiver;

CanTransceiver* can_transceiver_create(uint32_t busId, const char* name, bool loopback)
{
   CanTransceiver* xcvr = EC_NEW(CanTransceiver);
   xcvr->busId = busId;
   if(name) snprintf(xcvr->busName, sizeof(xcvr->busName), "%s", name);
   else snprintf(xcvr->busName, sizeof(xcvr->busName), "vcan%u", busId);

   xcvr->txQueue = ring_buffer_create(TRANSCEIVER_DEFAULT_QUEUE_SIZE);
   xcvr->rxQueue = ring_buffer_create(TRANSCEIVER_DEFAULT_QUEUE_SIZE);
   xcvr->isLoopbackEnabled = loopback;
   xcvr->totalFramesBroadcast = 0;
   xcvr->totalFramesReceived = 0;
   xcvr->arbitrationLossCount = 0;
   return xcvr;
}

void can_transceiver_destroy(CanTransceiver* xcvr)
{
   if(!xcvr) return;
   ring_buffer_destroy(xcvr->txQueue, free);
   ring_buffer_destroy(xcvr->rxQueue, free);
   EC_FREE(xcvr);
}

// Enqueues a frame for transmission
bool can_transceiver_transmit(CanTransceiver* xcvr, const CanFrame* frame)
{
   if(!xcvr || !frame) return false;

   CanFrame* copy = EC_NEW(CanFrame);
   *copy = *frame;

   if(!ring_buffer_push(xcvr->txQueue, copy))
   {
      EC_FREE(copy);
      return false; // Queue full
   }

   // If loopback is enabled, also deposit into local Rx queue
   if(xcvr->isLoopbackEnabled)
   {
      CanFrame* loopCopy = EC_NEW(CanFrame);
      *loopCopy = *frame;
      if(!ring_buffer_push(xcvr->rxQueue, loopCopy))
      {
         EC_FREE(loopCopy);
      }
   }

   xcvr->totalFramesBroadcast++;
   return true;
}

// Retrieves the next available received frame
bool can_transceiver_receive(CanTransceiver* xcvr, CanFrame* outFrame)
{
   if(!xcvr || !outFrame) return false;

   CanFrame* frame = (CanFrame*)ring_buffer_pop(xcvr->rxQueue);
   if(!frame) return false;

   *outFrame = *frame;
   EC_FREE(frame);
   xcvr->totalFramesReceived++;
   return true;
}

// Bus arbitration step: given multiple pending frames, the lowest arbitration ID wins
CanFrame* can_transceiver_arbitrate(CanFrame** pendingFrames, uint32_t count, uint32_t* winningIdx)
{
   if(!pendingFrames || count == 0) return NULL;

   uint32_t lowestId = 0xFFFFFFFFU;
   int bestIdx = -1;

   for(uint32_t i = 0; i < count; i++)
   {
      if(pendingFrames[i])
      {
         if(pendingFrames[i]->arbitrationId < lowestId)
         {
            lowestId = pendingFrames[i]->arbitrationId;
            bestIdx = (int)i;
         }
      }
   }

   if(bestIdx >= 0)
   {
      if(winningIdx) *winningIdx = (uint32_t)bestIdx;
      return pendingFrames[bestIdx];
   }
   return NULL;
}
