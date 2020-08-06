// src/someip/SomeIpSdParser.ec
// AUTOSAR SOME/IP Service Discovery (SOME/IP-SD) Entry and Option wire serialization and parsing.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "someip.eh"
#include "ec_runtime.h"

#define SOMEIP_SD_ENTRY_SIZE          16
#define SOMEIP_SD_IPV4_OPTION_SIZE    12
#define SOMEIP_SD_IPV4_OPTION_LEN_VAL 9

// Serializes a SOME/IP-SD message payload (flags, entries array, and options array)
uint32_t someip_sd_serialize(const SomeIpSdMessage* sdMsg, uint8_t* outBuf, uint32_t maxLen)
{
   if(!sdMsg || !outBuf)
   {
      return 0;
   }

   uint32_t entriesByteLen = sdMsg->entryCount * SOMEIP_SD_ENTRY_SIZE;
   uint32_t optionsByteLen = sdMsg->optionCount * SOMEIP_SD_IPV4_OPTION_SIZE;
   uint32_t totalLen = 4 + 4 + entriesByteLen + 4 + optionsByteLen;

   if(maxLen < totalLen)
   {
      return 0;
   }

   uint32_t offset = 0;

   // 1. Flags and Reserved (4 bytes)
   outBuf[offset++] = sdMsg->flags;
   outBuf[offset++] = 0x00;
   outBuf[offset++] = 0x00;
   outBuf[offset++] = 0x00;

   // 2. Length of Entries Array (4 bytes)
   outBuf[offset++] = (uint8_t)((entriesByteLen >> 24) & 0xFF);
   outBuf[offset++] = (uint8_t)((entriesByteLen >> 16) & 0xFF);
   outBuf[offset++] = (uint8_t)((entriesByteLen >> 8) & 0xFF);
   outBuf[offset++] = (uint8_t)(entriesByteLen & 0xFF);

   // 3. Entries Array (16 bytes per entry)
   for(uint32_t i = 0; i < sdMsg->entryCount; i++)
   {
      const SomeIpSdEntry* e = &sdMsg->entries[i];
      outBuf[offset++] = e->type;
      outBuf[offset++] = e->index1;
      outBuf[offset++] = e->index2;
      outBuf[offset++] = e->numOptions;
      outBuf[offset++] = (uint8_t)((e->serviceId >> 8) & 0xFF);
      outBuf[offset++] = (uint8_t)(e->serviceId & 0xFF);
      outBuf[offset++] = (uint8_t)((e->instanceId >> 8) & 0xFF);
      outBuf[offset++] = (uint8_t)(e->instanceId & 0xFF);
      outBuf[offset++] = e->majorVersion;
      // TTL is 24-bit big endian
      outBuf[offset++] = (uint8_t)((e->ttl >> 16) & 0xFF);
      outBuf[offset++] = (uint8_t)((e->ttl >> 8) & 0xFF);
      outBuf[offset++] = (uint8_t)(e->ttl & 0xFF);
      // Minor Version or Eventgroup ID
      outBuf[offset++] = (uint8_t)((e->minorOrEventgroup >> 24) & 0xFF);
      outBuf[offset++] = (uint8_t)((e->minorOrEventgroup >> 16) & 0xFF);
      outBuf[offset++] = (uint8_t)((e->minorOrEventgroup >> 8) & 0xFF);
      outBuf[offset++] = (uint8_t)(e->minorOrEventgroup & 0xFF);
   }

   // 4. Length of Options Array (4 bytes)
   outBuf[offset++] = (uint8_t)((optionsByteLen >> 24) & 0xFF);
   outBuf[offset++] = (uint8_t)((optionsByteLen >> 16) & 0xFF);
   outBuf[offset++] = (uint8_t)((optionsByteLen >> 8) & 0xFF);
   outBuf[offset++] = (uint8_t)(optionsByteLen & 0xFF);

   // 5. Options Array (12 bytes per IPv4 endpoint option)
   for(uint32_t i = 0; i < sdMsg->optionCount; i++)
   {
      const SomeIpSdOption* opt = &sdMsg->options[i];
      outBuf[offset++] = 0x00;
      outBuf[offset++] = SOMEIP_SD_IPV4_OPTION_LEN_VAL;
      outBuf[offset++] = opt->type; // Typically 0x04 (IPv4 endpoint)
      outBuf[offset++] = 0x00;      // Reserved
      outBuf[offset++] = opt->ipv4[0];
      outBuf[offset++] = opt->ipv4[1];
      outBuf[offset++] = opt->ipv4[2];
      outBuf[offset++] = opt->ipv4[3];
      outBuf[offset++] = 0x00;      // Reserved
      outBuf[offset++] = opt->protocol;
      outBuf[offset++] = (uint8_t)((opt->port >> 8) & 0xFF);
      outBuf[offset++] = (uint8_t)(opt->port & 0xFF);
   }

   return offset;
}

// Deserializes a SOME/IP-SD payload from raw buffer into structured SD container
bool someip_sd_deserialize(const uint8_t* inBuf, uint32_t inLen, SomeIpSdMessage* outSdMsg)
{
   if(!inBuf || !outSdMsg || inLen < 8)
   {
      return false;
   }

   memset(outSdMsg, 0, sizeof(SomeIpSdMessage));
   uint32_t offset = 0;

   // 1. Flags
   outSdMsg->flags = inBuf[offset++];
   offset += 3; // Skip 3 reserved bytes

   // 2. Length of Entries Array
   uint32_t entriesLen = ((uint32_t)inBuf[offset] << 24)     |
                         ((uint32_t)inBuf[offset + 1] << 16) |
                         ((uint32_t)inBuf[offset + 2] << 8)  |
                         ((uint32_t)inBuf[offset + 3]);
   offset += 4;

   if((offset + entriesLen + 4) > inLen)
   {
      return false;
   }

   uint32_t countEntries = entriesLen / SOMEIP_SD_ENTRY_SIZE;
   if(countEntries > SOMEIP_SD_MAX_ENTRIES)
   {
      countEntries = SOMEIP_SD_MAX_ENTRIES;
   }
   outSdMsg->entryCount = countEntries;

   for(uint32_t i = 0; i < countEntries; i++)
   {
      SomeIpSdEntry* e = &outSdMsg->entries[i];
      e->type           = inBuf[offset++];
      e->index1         = inBuf[offset++];
      e->index2         = inBuf[offset++];
      e->numOptions     = inBuf[offset++];
      e->serviceId      = ((uint16_t)inBuf[offset] << 8) | inBuf[offset + 1];
      offset += 2;
      e->instanceId     = ((uint16_t)inBuf[offset] << 8) | inBuf[offset + 1];
      offset += 2;
      e->majorVersion   = inBuf[offset++];
      e->ttl            = ((uint32_t)inBuf[offset] << 16) |
                          ((uint32_t)inBuf[offset + 1] << 8) |
                          ((uint32_t)inBuf[offset + 2]);
      offset += 3;
      e->minorOrEventgroup = ((uint32_t)inBuf[offset] << 24)     |
                             ((uint32_t)inBuf[offset + 1] << 16) |
                             ((uint32_t)inBuf[offset + 2] << 8)  |
                             ((uint32_t)inBuf[offset + 3]);
      offset += 4;
   }

   // 3. Length of Options Array
   if((offset + 4) > inLen)
   {
      return true; // No options section present
   }

   uint32_t optionsLen = ((uint32_t)inBuf[offset] << 24)     |
                         ((uint32_t)inBuf[offset + 1] << 16) |
                         ((uint32_t)inBuf[offset + 2] << 8)  |
                         ((uint32_t)inBuf[offset + 3]);
   offset += 4;

   if((offset + optionsLen) > inLen)
   {
      return false;
   }

   uint32_t countOpts = optionsLen / SOMEIP_SD_IPV4_OPTION_SIZE;
   if(countOpts > SOMEIP_SD_MAX_OPTIONS)
   {
      countOpts = SOMEIP_SD_MAX_OPTIONS;
   }
   outSdMsg->optionCount = countOpts;

   for(uint32_t i = 0; i < countOpts; i++)
   {
      SomeIpSdOption* opt = &outSdMsg->options[i];
      offset += 2; // Skip 2-byte option length
      opt->type = inBuf[offset++];
      offset++;    // Skip reserved byte
      opt->ipv4[0] = inBuf[offset++];
      opt->ipv4[1] = inBuf[offset++];
      opt->ipv4[2] = inBuf[offset++];
      opt->ipv4[3] = inBuf[offset++];
      offset++;    // Skip reserved byte
      opt->protocol = inBuf[offset++];
      opt->port = ((uint16_t)inBuf[offset] << 8) | inBuf[offset + 1];
      offset += 2;
   }

   return true;
}
