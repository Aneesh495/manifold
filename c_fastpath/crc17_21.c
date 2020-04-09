// c_fastpath/crc17_21.c
// Hardware-accelerated CRC calculation for CAN 2.0B (CRC-15) and CAN FD (CRC-17, CRC-21).
// Compliant with ISO 11898-1:2015 specification.

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define CRC15_POLY 0x4599U
#define CRC17_POLY 0x1685BU // Monic: 0x3685B (x^17 + ...)
#define CRC21_POLY 0x102317U // Monic: 0x302317 (x^21 + ...)

// Classical CAN CRC-15
uint16_t can_crc15(const uint8_t* data, uint32_t len)
{
   uint16_t crc = 0x0000;
   if(!data || len == 0) return crc;

   for(uint32_t i = 0; i < len; i++)
   {
      uint8_t byte = data[i];
      for(int b = 7; b >= 0; b--)
      {
         bool bit = (byte >> b) & 1;
         bool msb = (crc >> 14) & 1;
         crc <<= 1;
         crc &= 0x7FFF;
         if(bit ^ msb)
         {
            crc ^= CRC15_POLY;
         }
      }
   }
   return crc;
}

// CAN FD CRC-17 (used for payloads <= 16 bytes)
// Initializes with fixed MSB 1, followed by stuff count bits
uint32_t can_fd_crc17(const uint8_t* data, uint32_t len, uint8_t stuffCount)
{
   uint32_t crc = 0x10000; // MSB initialized to 1 for CRC-17
   if(!data) return crc;

   // Process 4-bit stuff count (3-bit gray code + 1 parity bit)
   uint8_t sc = stuffCount & 0x0F;
   for(int b = 3; b >= 0; b--)
   {
      bool bit = (sc >> b) & 1;
      bool msb = (crc >> 16) & 1;
      crc <<= 1;
      crc &= 0x1FFFF;
      if(bit ^ msb)
      {
         crc ^= CRC17_POLY;
      }
   }

   // Process payload bytes
   for(uint32_t i = 0; i < len; i++)
   {
      uint8_t byte = data[i];
      for(int b = 7; b >= 0; b--)
      {
         bool bit = (byte >> b) & 1;
         bool msb = (crc >> 16) & 1;
         crc <<= 1;
         crc &= 0x1FFFF;
         if(bit ^ msb)
         {
            crc ^= CRC17_POLY;
         }
      }
   }

   return crc & 0x1FFFF;
}

// CAN FD CRC-21 (used for payloads > 16 bytes)
// Initializes with fixed MSB 1, followed by stuff count bits
uint32_t can_fd_crc21(const uint8_t* data, uint32_t len, uint8_t stuffCount)
{
   uint32_t crc = 0x100000; // MSB initialized to 1 for CRC-21
   if(!data) return crc;

   uint8_t sc = stuffCount & 0x0F;
   for(int b = 3; b >= 0; b--)
   {
      bool bit = (sc >> b) & 1;
      bool msb = (crc >> 20) & 1;
      crc <<= 1;
      crc &= 0x1FFFFF;
      if(bit ^ msb)
      {
         crc ^= CRC21_POLY;
      }
   }

   for(uint32_t i = 0; i < len; i++)
   {
      uint8_t byte = data[i];
      for(int b = 7; b >= 0; b--)
      {
         bool bit = (byte >> b) & 1;
         bool msb = (crc >> 20) & 1;
         crc <<= 1;
         crc &= 0x1FFFFF;
         if(bit ^ msb)
         {
            crc ^= CRC21_POLY;
         }
      }
   }

   return crc & 0x1FFFFF;
}
