// src/core/RingBuffer.ec
// Lock-free circular ring buffer implementation for deterministic frame queuing.

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "types.eh"
#include "core.eh"
#include "ec_runtime.h"

RingBuffer* ring_buffer_create(uint32_t capacity)
{
   RingBuffer* rb = EC_NEW(RingBuffer);
   rb->capacity = (capacity > 0) ? capacity : RING_BUFFER_DEFAULT_CAPACITY;
   rb->slots = (void**)ec_runtime_alloc(sizeof(void*) * rb->capacity);
   rb->head = 0;
   rb->tail = 0;
   rb->count = 0;
   rb->totalEnqueued = 0;
   rb->totalDequeued = 0;
   rb->overrunCount = 0;
   rb->peakWatermark = 0;
   return rb;
}

void ring_buffer_destroy(RingBuffer* rb, void (*itemFree)(void*))
{
   if(!rb) return;
   if(itemFree)
   {
      while(rb->count > 0)
      {
         void* item = rb->slots[rb->tail];
         if(item) itemFree(item);
         rb->tail = (rb->tail + 1) % rb->capacity;
         rb->count--;
      }
   }
   EC_FREE(rb->slots);
   EC_FREE(rb);
}

bool ring_buffer_push(RingBuffer* rb, void* item)
{
   if(!rb || !item) return false;
   if(rb->count >= rb->capacity)
   {
      rb->overrunCount++;
      return false;
   }

   rb->slots[rb->head] = item;
   rb->head = (rb->head + 1) % rb->capacity;
   rb->count++;
   rb->totalEnqueued++;

   if(rb->count > rb->peakWatermark)
   {
      rb->peakWatermark = rb->count;
   }
   return true;
}

void* ring_buffer_pop(RingBuffer* rb)
{
   if(!rb || rb->count == 0) return NULL;

   void* item = rb->slots[rb->tail];
   rb->slots[rb->tail] = NULL;
   rb->tail = (rb->tail + 1) % rb->capacity;
   rb->count--;
   rb->totalDequeued++;
   return item;
}

void* ring_buffer_peek(const RingBuffer* rb)
{
   if(!rb || rb->count == 0) return NULL;
   return rb->slots[rb->tail];
}

uint32_t ring_buffer_size(const RingBuffer* rb)
{
   return rb ? rb->count : 0;
}

bool ring_buffer_is_empty(const RingBuffer* rb)
{
   return !rb || (rb->count == 0);
}

bool ring_buffer_is_full(const RingBuffer* rb)
{
   return rb && (rb->count >= rb->capacity);
}
