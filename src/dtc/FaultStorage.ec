// src/dtc/FaultStorage.ec
// Simulated non-volatile flash storage with wear-leveling journal for DTC persistence.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "dtc.eh"
#include "ec_runtime.h"

#define NVRAM_SECTOR_SIZE 4096
#define NVRAM_MAGIC       0xAA55

typedef struct NvramHeader
{
   uint16_t magic;
   uint16_t sequence;
   uint16_t payloadSize;
   uint16_t checksum;
} NvramHeader;

static uint8_t g_nvramStorage[NVRAM_SECTOR_SIZE];
static uint16_t g_currentSequence = 0;

static uint16_t compute_nvram_checksum(const uint8_t* data, uint32_t len)
{
   uint16_t csum = 0xFFFF;
   for(uint32_t i = 0; i < len; i++)
   {
      csum = (uint16_t)((csum >> 8) | (csum << 8));
      csum ^= data[i];
   }
   return csum;
}

// Persists all current active DTC entries to non-volatile storage
bool fault_storage_commit(const FaultManager* mgr)
{
   if(!mgr) return false;

   uint32_t payloadSize = mgr->count * sizeof(DtcEntry);
   if(sizeof(NvramHeader) + payloadSize > NVRAM_SECTOR_SIZE)
   {
      return false; // Storage full
   }

   NvramHeader header;
   header.magic = NVRAM_MAGIC;
   header.sequence = ++g_currentSequence;
   header.payloadSize = (uint16_t)payloadSize;
   header.checksum = compute_nvram_checksum((const uint8_t*)mgr->entries, payloadSize);

   memcpy(g_nvramStorage, &header, sizeof(NvramHeader));
   memcpy(g_nvramStorage + sizeof(NvramHeader), mgr->entries, payloadSize);
   return true;
}

// Restores DTC entries from non-volatile storage on ECU power-up
bool fault_storage_restore(FaultManager* mgr)
{
   if(!mgr) return false;

   NvramHeader header;
   memcpy(&header, g_nvramStorage, sizeof(NvramHeader));

   if(header.magic != NVRAM_MAGIC)
   {
      return false; // Uninitialized storage
   }

   if(sizeof(NvramHeader) + header.payloadSize > NVRAM_SECTOR_SIZE)
   {
      return false; // Corrupt payload size
   }

   const uint8_t* payload = g_nvramStorage + sizeof(NvramHeader);
   uint16_t computed = compute_nvram_checksum(payload, header.payloadSize);
   if(computed != header.checksum)
   {
      return false; // Checksum mismatch
   }

   uint32_t entryCount = header.payloadSize / sizeof(DtcEntry);
   if(entryCount > MAX_DTC_ENTRIES) entryCount = MAX_DTC_ENTRIES;

   mgr->count = entryCount;
   memcpy(mgr->entries, payload, entryCount * sizeof(DtcEntry));
   g_currentSequence = header.sequence;
   return true;
}
