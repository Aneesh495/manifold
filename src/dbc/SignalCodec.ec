// src/dbc/SignalCodec.ec
// Bitfield extraction, encoding, scaling, and offset computation for DBC signals.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#include "types.eh"
#include "dbc.eh"
#include "ec_runtime.h"

// Extracts raw unsigned bits from payload in Intel (little-endian) bit numbering
static uint64_t dbc_extract_intel_bits(const uint8_t* payload, uint32_t payloadLen, uint32_t startBit, uint32_t bitLength)
{
   uint64_t raw = 0;
   for(uint32_t i = 0; i < bitLength; i++)
   {
      uint32_t bitIdx = startBit + i;
      uint32_t byteIdx = bitIdx / 8;
      uint32_t bitInByte = bitIdx % 8;

      if(byteIdx < payloadLen)
      {
         if((payload[byteIdx] >> bitInByte) & 0x01)
         {
            raw |= (1ULL << i);
         }
      }
   }
   return raw;
}

// Injects raw bits into payload in Intel (little-endian) bit numbering
static void dbc_inject_intel_bits(uint8_t* payload, uint32_t payloadLen, uint32_t startBit, uint32_t bitLength, uint64_t raw)
{
   for(uint32_t i = 0; i < bitLength; i++)
   {
      uint32_t bitIdx = startBit + i;
      uint32_t byteIdx = bitIdx / 8;
      uint32_t bitInByte = bitIdx % 8;

      if(byteIdx < payloadLen)
      {
         if((raw >> i) & 0x01)
         {
            payload[byteIdx] |= (uint8_t)(1 << bitInByte);
         }
         else
         {
            payload[byteIdx] &= (uint8_t)~(1 << bitInByte);
         }
      }
   }
}

// Extracts raw bits from payload in Motorola (big-endian) bit numbering
static uint64_t dbc_extract_motorola_bits(const uint8_t* payload, uint32_t payloadLen, uint32_t startBit, uint32_t bitLength)
{
   uint64_t raw = 0;
   uint32_t currentBit = startBit;

   for(uint32_t i = 0; i < bitLength; i++)
   {
      uint32_t byteIdx = currentBit / 8;
      uint32_t bitInByte = currentBit % 8;

      if(byteIdx < payloadLen)
      {
         if((payload[byteIdx] >> bitInByte) & 0x01)
         {
            raw |= (1ULL << (bitLength - 1 - i));
         }
      }

      // Motorola bit walk: bitInByte decreases down to 0, then wraps to next byte bit 7
      if(bitInByte == 0)
      {
         currentBit += 15;
      }
      else
      {
         currentBit--;
      }
   }
   return raw;
}

// Injects raw bits into payload in Motorola (big-endian) bit numbering
static void dbc_inject_motorola_bits(uint8_t* payload, uint32_t payloadLen, uint32_t startBit, uint32_t bitLength, uint64_t raw)
{
   uint32_t currentBit = startBit;

   for(uint32_t i = 0; i < bitLength; i++)
   {
      uint32_t byteIdx = currentBit / 8;
      uint32_t bitInByte = currentBit % 8;

      if(byteIdx < payloadLen)
      {
         if((raw >> (bitLength - 1 - i)) & 0x01)
         {
            payload[byteIdx] |= (uint8_t)(1 << bitInByte);
         }
         else
         {
            payload[byteIdx] &= (uint8_t)~(1 << bitInByte);
         }
      }

      if(bitInByte == 0)
      {
         currentBit += 15;
      }
      else
      {
         currentBit--;
      }
   }
}

// Decodes a physical engineering value from a CAN payload given signal definition
double dbc_decode_signal(const DbcSignal* sig, const uint8_t* payload, uint32_t payloadLen)
{
   if(!sig || !payload || payloadLen == 0)
   {
      return 0.0;
   }

   uint64_t raw = 0;
   if(sig->endianness == ENDIAN_INTEL) // Intel
   {
      raw = dbc_extract_intel_bits(payload, payloadLen, sig->startBit, sig->bitLength);
   }
   else // Motorola
   {
      raw = dbc_extract_motorola_bits(payload, payloadLen, sig->startBit, sig->bitLength);
   }

   // Sign extension if signal is signed
   if(sig->isSigned && sig->bitLength > 0 && sig->bitLength < 64)
   {
      uint64_t signBit = 1ULL << (sig->bitLength - 1);
      if(raw & signBit)
      {
         uint64_t mask = ~0ULL << sig->bitLength;
         raw |= mask;
         int64_t signedRaw = (int64_t)raw;
         return ((double)signedRaw * sig->factor) + sig->offset;
      }
   }

   return ((double)raw * sig->factor) + sig->offset;
}

// Encodes a physical engineering value into a CAN payload given signal definition
bool dbc_encode_signal(const DbcSignal* sig, double physicalValue, uint8_t* payload, uint32_t payloadLen)
{
   if(!sig || !payload || payloadLen == 0)
   {
      return false;
   }

   // Clamping to configured min/max
   if(sig->min < sig->max)
   {
      if(physicalValue < sig->min) physicalValue = sig->min;
      if(physicalValue > sig->max) physicalValue = sig->max;
   }

   double scaled = (physicalValue - sig->offset) / (sig->factor != 0.0 ? sig->factor : 1.0);
   int64_t rawSigned = (int64_t)llround(scaled);
   uint64_t raw = (uint64_t)rawSigned;

   // Mask to bitLength
   if(sig->bitLength < 64)
   {
      raw &= (1ULL << sig->bitLength) - 1;
   }

   if(sig->endianness == ENDIAN_INTEL)
   {
      dbc_inject_intel_bits(payload, payloadLen, sig->startBit, sig->bitLength, raw);
   }
   else
   {
      dbc_inject_motorola_bits(payload, payloadLen, sig->startBit, sig->bitLength, raw);
   }

   return true;
}
