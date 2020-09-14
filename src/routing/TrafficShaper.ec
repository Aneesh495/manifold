// src/routing/TrafficShaper.ec
// Token bucket traffic shaper and priority egress queue for in-vehicle network gateway.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "routing.eh"
#include "ec_runtime.h"

// Initializes a token bucket rate limiter
void traffic_shaper_init(TokenBucket* bucket, uint32_t capacity, uint32_t refillRatePerSec)
{
   if(!bucket) return;
   bucket->capacity         = capacity;
   bucket->currentTokens    = capacity;
   bucket->refillRatePerSec = refillRatePerSec;
   bucket->lastRefillMs     = 0;
}

// Attempts to consume tokens from the bucket based on current timestamp
bool traffic_shaper_consume(TokenBucket* bucket, uint32_t tokens, uint64_t currentMs)
{
   if(!bucket) return false;

   // Refill tokens based on elapsed wall-clock time
   if(currentMs > bucket->lastRefillMs)
   {
      uint64_t elapsedMs = currentMs - bucket->lastRefillMs;
      uint64_t tokensToAdd = (elapsedMs * (uint64_t)bucket->refillRatePerSec) / 1000ULL;
      if(tokensToAdd > 0)
      {
         uint64_t newTotal = (uint64_t)bucket->currentTokens + tokensToAdd;
         bucket->currentTokens = (newTotal > (uint64_t)bucket->capacity) ? bucket->capacity : (uint32_t)newTotal;
         bucket->lastRefillMs  = currentMs;
      }
   }
   else if(bucket->lastRefillMs == 0)
   {
      bucket->lastRefillMs = currentMs;
   }

   if(bucket->currentTokens >= tokens)
   {
      bucket->currentTokens -= tokens;
      return true;
   }

   return false;
}

// Initializes an egress priority queue
void egress_queue_init(EgressQueue* q)
{
   if(!q) return;
   memset(q, 0, sizeof(EgressQueue));
}

// Pushes a frame into the egress queue, sorted descending by priority (highest priority at head)
bool egress_queue_push(EgressQueue* q, const CanFrame* frame, uint8_t priority)
{
   if(!q || !frame || q->count >= EGRESS_QUEUE_CAPACITY)
   {
      return false;
   }

   // Find insertion index to maintain descending priority order
   uint32_t insertIdx = q->count;
   for(uint32_t i = 0; i < q->count; i++)
   {
      if(priority > q->items[i].priority)
      {
         insertIdx = i;
         break;
      }
   }

   // Shift elements right
   for(uint32_t i = q->count; i > insertIdx; i--)
   {
      q->items[i] = q->items[i - 1];
   }

   q->items[insertIdx].frame    = *frame;
   q->items[insertIdx].priority = priority;
   q->count++;

   return true;
}

// Pops the highest-priority frame from the front of the queue
bool egress_queue_pop(EgressQueue* q, CanFrame* outFrame)
{
   if(!q || !outFrame || q->count == 0)
   {
      return false;
   }

   *outFrame = q->items[0].frame;

   // Shift remaining items left
   for(uint32_t i = 1; i < q->count; i++)
   {
      q->items[i - 1] = q->items[i];
   }
   q->count--;

   return true;
}
