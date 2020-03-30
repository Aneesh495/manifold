// src/core/BitStream.ec
// Motorola (Big Endian) and Intel (Little Endian) bitfield extraction and injection engine.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "ec_runtime.h"

// Extracts an unsigned bitfield from a payload according to DBC byte order specifications
uint64_t bitstream_extract_unsigned(const uint8_t* payload, uint32_t payloadLen,
                                    uint32_t startBit, uint32_t bitLength,
                                    Endianness endianness)
{
   if(!payload || payloadLen == 0 || bitLength == 0 || bitLength > 64)
   {
      return 0;
   }

   uint64_t result = 0;

   if(endianness == ENDIAN_INTEL)
   {
      // Intel (Standard Little Endian)
      for(uint32_t i = 0; i < bitLength; i++)
      {
         uint32_t bitPos = startBit + i;
         uint32_t byteIdx = bitPos / 8;
         uint32_t bitOffset = bitPos % 8;

         if(byteIdx < payloadLen)
         {
            uint8_t bit = (uint8_t)((payload[byteIdx] >> bitOffset) & 0x01);
            result |= ((uint64_t)bit << i);
         }
      }
   }
   else
   {
      // Motorola (Big Endian)
      // In CAN DBC Motorola, startBit designates the most significant bit or least significant bit
      // standard DBC convention: startBit is MSB of the signal.
      int32_t currentBit = (int32_t)startBit;
      for(uint32_t i = 0; i < bitLength; i++)
      {
         uint32_t byteIdx = (uint32_t)(currentBit / 8);
         uint32_t bitOffset = (uint32_t)(currentBit % 8);

         if(byteIdx < payloadLen)
         {
            uint8_t bit = (uint8_t)((payload[byteIdx] >> bitOffset) & 0x01);
            result = (result << 1) | (uint64_t)bit;
         }

         if((currentBit % 8) == 0)
         {
            currentBit += 15; // Move to next higher byte MSB
         }
         else
         {
            currentBit--;
         }
      }
   }

   return result;
}

// Extracts a signed bitfield with two's complement sign-extension
int64_t bitstream_extract_signed(const uint8_t* payload, uint32_t payloadLen,
                                uint32_t startBit, uint32_t bitLength,
                                Endianness endianness)
{
   uint64_t raw = bitstream_extract_unsigned(payload, payloadLen, startBit, bitLength, endianness);
   if(bitLength == 0 || bitLength >= 64)
   {
      return (int64_t)raw;
   }

   uint64_t signBitMask = 1ULL << (bitLength - 1);
   if(raw & signBitMask)
   {
      // Sign-extend negative value
      uint64_t mask = ~0ULL << bitLength;
      return (int64_t)(raw | mask);
   }
   return (int64_t)raw;
}

// Injects an unsigned bitfield into a payload buffer
bool bitstream_inject_unsigned(uint8_t* payload, uint32_t payloadLen,
                               uint32_t startBit, uint32_t bitLength,
                               Endianness endianness, uint64_t value)
{
   if(!payload || payloadLen == 0 || bitLength == 0 || bitLength > 64)
   {
      return false;
   }

   if(endianness == ENDIAN_INTEL)
   {
      for(uint32_t i = 0; i < bitLength; i++)
      {
         uint32_t bitPos = startBit + i;
         uint32_t byteIdx = bitPos / 8;
         uint32_t bitOffset = bitPos % 8;

         if(byteIdx < payloadLen)
         {
            uint8_t bit = (uint8_t)((value >> i) & 0x01);
            payload[byteIdx] &= (uint8_t)(~(1 << bitOffset));
            payload[byteIdx] |= (uint8_t)(bit << bitOffset);
         }
      }
   }
   else
   {
      int32_t currentBit = (int32_t)startBit;
      for(uint32_t i = 0; i < bitLength; i++)
      {
         uint32_t byteIdx = (uint32_t)(currentBit / 8);
         uint32_t bitOffset = (uint32_t)(currentBit % 8);

         if(byteIdx < payloadLen)
         {
            uint32_t shift = bitLength - 1 - i;
            uint8_t bit = (uint8_t)((value >> shift) & 0x01);
            payload[byteIdx] &= (uint8_t)(~(1 << bitOffset));
            payload[byteIdx] |= (uint8_t)(bit << bitOffset);
         }

         if((currentBit % 8) == 0)
         {
            currentBit += 15;
         }
         else
         {
            currentBit--;
         }
      }
   }

   return true;
}
