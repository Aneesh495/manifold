// src/someip/SomeIpSerializer.ec
// AUTOSAR SOME/IP payload serializer and deserializer for primitives, structs, and arrays.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "someip.eh"
#include "ec_runtime.h"

// Initializes a serialization context with output buffer and capacity
void someip_serializer_init(SomeIpSerializer* s, uint8_t* buf, uint32_t capacity)
{
   if(!s) return;
   s->buffer = buf;
   s->capacity = capacity;
   s->offset = 0;
}

// Serializes an 8-bit unsigned integer
bool someip_serialize_uint8(SomeIpSerializer* s, uint8_t val)
{
   if(!s || !s->buffer || (s->offset + 1) > s->capacity)
   {
      return false;
   }
   s->buffer[s->offset++] = val;
   return true;
}

// Serializes a 16-bit unsigned integer in big-endian network byte order
bool someip_serialize_uint16(SomeIpSerializer* s, uint16_t val)
{
   if(!s || !s->buffer || (s->offset + 2) > s->capacity)
   {
      return false;
   }
   s->buffer[s->offset++] = (uint8_t)((val >> 8) & 0xFF);
   s->buffer[s->offset++] = (uint8_t)(val & 0xFF);
   return true;
}

// Serializes a 32-bit unsigned integer in big-endian network byte order
bool someip_serialize_uint32(SomeIpSerializer* s, uint32_t val)
{
   if(!s || !s->buffer || (s->offset + 4) > s->capacity)
   {
      return false;
   }
   s->buffer[s->offset++] = (uint8_t)((val >> 24) & 0xFF);
   s->buffer[s->offset++] = (uint8_t)((val >> 16) & 0xFF);
   s->buffer[s->offset++] = (uint8_t)((val >> 8) & 0xFF);
   s->buffer[s->offset++] = (uint8_t)(val & 0xFF);
   return true;
}

// Serializes a 64-bit unsigned integer in big-endian network byte order
bool someip_serialize_uint64(SomeIpSerializer* s, uint64_t val)
{
   if(!s || !s->buffer || (s->offset + 8) > s->capacity)
   {
      return false;
   }
   for(int i = 7; i >= 0; i--)
   {
      s->buffer[s->offset++] = (uint8_t)((val >> (i * 8)) & 0xFF);
   }
   return true;
}

// Serializes a 32-bit single-precision floating point number (IEEE 754 big-endian)
bool someip_serialize_float32(SomeIpSerializer* s, float val)
{
   union { float f; uint32_t u; } conv;
   conv.f = val;
   return someip_serialize_uint32(s, conv.u);
}

// Serializes a 64-bit double-precision floating point number (IEEE 754 big-endian)
bool someip_serialize_float64(SomeIpSerializer* s, double val)
{
   union { double d; uint64_t u; } conv;
   conv.d = val;
   return someip_serialize_uint64(s, conv.u);
}

// Serializes raw byte arrays
bool someip_serialize_bytes(SomeIpSerializer* s, const uint8_t* data, uint32_t len)
{
   if(!s || !s->buffer || !data || (s->offset + len) > s->capacity)
   {
      return false;
   }
   memcpy(s->buffer + s->offset, data, len);
   s->offset += len;
   return true;
}

// Serializes a dynamic UTF-8 string with a 4-byte big-endian length prefix
bool someip_serialize_string(SomeIpSerializer* s, const char* str)
{
   if(!s || !str) return false;
   uint32_t strLen = (uint32_t)strlen(str);
   if(!someip_serialize_uint32(s, strLen))
   {
      return false;
   }
   return someip_serialize_bytes(s, (const uint8_t*)str, strLen);
}

// Initializes a deserialization context with input buffer and length
void someip_deserializer_init(SomeIpDeserializer* d, const uint8_t* buf, uint32_t length)
{
   if(!d) return;
   d->buffer = buf;
   d->length = length;
   d->offset = 0;
}

// Deserializes an 8-bit unsigned integer
bool someip_deserialize_uint8(SomeIpDeserializer* d, uint8_t* outVal)
{
   if(!d || !d->buffer || !outVal || (d->offset + 1) > d->length)
   {
      return false;
   }
   *outVal = d->buffer[d->offset++];
   return true;
}

// Deserializes a 16-bit big-endian unsigned integer
bool someip_deserialize_uint16(SomeIpDeserializer* d, uint16_t* outVal)
{
   if(!d || !d->buffer || !outVal || (d->offset + 2) > d->length)
   {
      return false;
   }
   *outVal = ((uint16_t)d->buffer[d->offset] << 8) | d->buffer[d->offset + 1];
   d->offset += 2;
   return true;
}

// Deserializes a 32-bit big-endian unsigned integer
bool someip_deserialize_uint32(SomeIpDeserializer* d, uint32_t* outVal)
{
   if(!d || !d->buffer || !outVal || (d->offset + 4) > d->length)
   {
      return false;
   }
   *outVal = ((uint32_t)d->buffer[d->offset] << 24)     |
             ((uint32_t)d->buffer[d->offset + 1] << 16) |
             ((uint32_t)d->buffer[d->offset + 2] << 8)  |
             ((uint32_t)d->buffer[d->offset + 3]);
   d->offset += 4;
   return true;
}

// Deserializes a 64-bit big-endian unsigned integer
bool someip_deserialize_uint64(SomeIpDeserializer* d, uint64_t* outVal)
{
   if(!d || !d->buffer || !outVal || (d->offset + 8) > d->length)
   {
      return false;
   }
   uint64_t val = 0;
   for(int i = 0; i < 8; i++)
   {
      val = (val << 8) | d->buffer[d->offset + i];
   }
   d->offset += 8;
   *outVal = val;
   return true;
}

// Deserializes a 32-bit single-precision floating point number
bool someip_deserialize_float32(SomeIpDeserializer* d, float* outVal)
{
   if(!outVal) return false;
   union { float f; uint32_t u; } conv;
   if(!someip_deserialize_uint32(d, &conv.u))
   {
      return false;
   }
   *outVal = conv.f;
   return true;
}

// Deserializes a 64-bit double-precision floating point number
bool someip_deserialize_float64(SomeIpDeserializer* d, double* outVal)
{
   if(!outVal) return false;
   union { double d; uint64_t u; } conv;
   if(!someip_deserialize_uint64(d, &conv.u))
   {
      return false;
   }
   *outVal = conv.d;
   return true;
}

// Deserializes raw byte arrays
bool someip_deserialize_bytes(SomeIpDeserializer* d, uint8_t* outData, uint32_t len)
{
   if(!d || !d->buffer || !outData || (d->offset + len) > d->length)
   {
      return false;
   }
   memcpy(outData, d->buffer + d->offset, len);
   d->offset += len;
   return true;
}

// Deserializes a dynamic length-prefixed string
bool someip_deserialize_string(SomeIpDeserializer* d, char* outStr, uint32_t maxStrLen)
{
   if(!d || !outStr || maxStrLen == 0) return false;

   uint32_t strLen = 0;
   if(!someip_deserialize_uint32(d, &strLen))
   {
      return false;
   }

   if((d->offset + strLen) > d->length || strLen >= maxStrLen)
   {
      return false;
   }

   memcpy(outStr, d->buffer + d->offset, strLen);
   outStr[strLen] = '\0';
   d->offset += strLen;
   return true;
}
