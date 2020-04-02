// include/core.eh
// Core memory buffers, lock-free ring buffers, and bitstream manipulation.

#ifndef MANIFOLD_CORE_EH
#define MANIFOLD_CORE_EH

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "types.eh"
#include "ec_runtime.h"

// Safe byte buffer with dynamic capacity expansion and bound checks
typedef struct ByteBuffer
{
   uint8_t* rawData;
   uint32_t length;
   uint32_t capacity;
} ByteBuffer;

void byte_buffer_init(ByteBuffer* buf, uint32_t initialCap);
void byte_buffer_free(ByteBuffer* buf);
bool byte_buffer_append(ByteBuffer* buf, const uint8_t* src, uint32_t len);
bool byte_buffer_append_u8(ByteBuffer* buf, uint8_t val);
bool byte_buffer_append_u16_be(ByteBuffer* buf, uint16_t val);
bool byte_buffer_append_u32_be(ByteBuffer* buf, uint32_t val);
void byte_buffer_clear(ByteBuffer* buf);

#define RING_BUFFER_DEFAULT_CAPACITY 512

typedef struct RingBuffer
{
   void** slots;
   uint32_t capacity;
   uint32_t head;
   uint32_t tail;
   uint32_t count;
   uint64_t totalEnqueued;
   uint64_t totalDequeued;
   uint64_t overrunCount;
   uint32_t peakWatermark;
} RingBuffer;

RingBuffer* ring_buffer_create(uint32_t capacity);
void ring_buffer_destroy(RingBuffer* rb, void (*itemFree)(void*));
bool ring_buffer_push(RingBuffer* rb, void* item);
void* ring_buffer_pop(RingBuffer* rb);
void* ring_buffer_peek(const RingBuffer* rb);
uint32_t ring_buffer_size(const RingBuffer* rb);
bool ring_buffer_is_empty(const RingBuffer* rb);
bool ring_buffer_is_full(const RingBuffer* rb);

uint64_t bitstream_extract_unsigned(const uint8_t* payload, uint32_t payloadLen,
                                    uint32_t startBit, uint32_t bitLength,
                                    Endianness endianness);
int64_t bitstream_extract_signed(const uint8_t* payload, uint32_t payloadLen,
                                uint32_t startBit, uint32_t bitLength,
                                Endianness endianness);
bool bitstream_inject_unsigned(uint8_t* payload, uint32_t payloadLen,
                               uint32_t startBit, uint32_t bitLength,
                               Endianness endianness, uint64_t value);

#endif // MANIFOLD_CORE_EH
