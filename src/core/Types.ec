// src/core/Types.ec
// Core memory buffer, diagnostic context, and byte array abstractions in eC.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "types.eh"
#include "core.eh"
#include "ec_runtime.h"

void byte_buffer_init(ByteBuffer* buf, uint32_t initialCap)
{
   if(!buf) return;
   buf->capacity = (initialCap > 0) ? initialCap : 64;
   buf->rawData = (uint8_t*)ec_runtime_alloc(buf->capacity);
   buf->length = 0;
}

void byte_buffer_free(ByteBuffer* buf)
{
   if(!buf) return;
   EC_FREE(buf->rawData);
   buf->length = 0;
   buf->capacity = 0;
}

bool byte_buffer_append(ByteBuffer* buf, const uint8_t* src, uint32_t len)
{
   if(!buf || !src || len == 0) return false;
   if(buf->length + len > buf->capacity)
   {
      uint32_t newCap = buf->capacity * 2;
      if(newCap < buf->length + len) newCap = buf->length + len + 64;
      buf->rawData = (uint8_t*)ec_runtime_realloc(buf->rawData, newCap);
      buf->capacity = newCap;
   }
   memcpy(buf->rawData + buf->length, src, len);
   buf->length += len;
   return true;
}

bool byte_buffer_append_u8(ByteBuffer* buf, uint8_t val)
{
   return byte_buffer_append(buf, &val, 1);
}

bool byte_buffer_append_u16_be(ByteBuffer* buf, uint16_t val)
{
   uint8_t b[2];
   b[0] = (uint8_t)((val >> 8) & 0xFF);
   b[1] = (uint8_t)(val & 0xFF);
   return byte_buffer_append(buf, b, 2);
}

bool byte_buffer_append_u32_be(ByteBuffer* buf, uint32_t val)
{
   uint8_t b[4];
   b[0] = (uint8_t)((val >> 24) & 0xFF);
   b[1] = (uint8_t)((val >> 16) & 0xFF);
   b[2] = (uint8_t)((val >> 8) & 0xFF);
   b[3] = (uint8_t)(val & 0xFF);
   return byte_buffer_append(buf, b, 4);
}

void byte_buffer_clear(ByteBuffer* buf)
{
   if(buf) buf->length = 0;
}
