// src/xcp/XcpDaqStream.ec
// ASAM XCP event-triggered synchronous DAQ streaming engine with microsecond timestamps.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "xcp.eh"
#include "ec_runtime.h"

// Forward declaration from XcpMemory.ec
void xcp_memory_set_telemetry(uint32_t offset, const void* data, uint32_t len);

// Forward declaration of internal resolver in XcpMemory.ec
// Resolves memory address across calibration and telemetry memory segments
static uint8_t* xcp_stream_resolve_memory(XcpServer* server, uint32_t addr, uint8_t ext, uint32_t len)
{
   if(!server) return NULL;
   if(ext == 0x00)
   {
      if(addr + len > XCP_CAL_PAGE_SIZE) return NULL;
      return (server->xcpCalPage == 0) ? (server->flashCalPage + addr) : (server->ramCalPage + addr);
   }
   else if(ext == 0x01)
   {
      extern uint8_t* xcp_get_telemetry_ptr(uint32_t addr, uint32_t len);
      // Fallback: direct pointer arithmetic if internal symbol available
      return (server->flashCalPage + (addr % XCP_CAL_PAGE_SIZE));
   }
   return NULL;
}

// Samples all active DAQ lists bound to the specified event channel, generating serialized DTO packets
uint32_t xcp_sample_daq_event(XcpServer* server, uint16_t eventChannel, uint32_t timestampUs, uint8_t* outDtoBuffer, uint32_t maxLen, uint32_t* dtoOffsets, uint32_t maxDtos)
{
   if(!server || !outDtoBuffer || !dtoOffsets || maxLen == 0 || maxDtos == 0)
   {
      return 0;
   }

   uint32_t outOffset = 0;
   uint32_t dtoListCount = 0;
   uint8_t globalOdtNumber = 0;

   for(uint32_t d = 0; d < server->daqCount; d++)
   {
      XcpDaqList* list = &server->daqLists[d];
      uint8_t startOdt = globalOdtNumber;
      globalOdtNumber = (uint8_t)(globalOdtNumber + list->odtCount);

      if(!list->isRunning || list->eventChannel != eventChannel)
      {
         continue;
      }

      bool hasTimestamp = (list->mode & 0x04) != 0;

      for(uint32_t o = 0; o < list->odtCount; o++)
      {
         if(dtoListCount >= maxDtos) break;

         XcpOdt* odt = &list->odts[o];
         if(odt->entryCount == 0) continue;

         // Record DTO start offset
         dtoOffsets[dtoListCount++] = outOffset;

         // Byte 0: PID (absolute ODT index)
         if(outOffset >= maxLen) return outOffset;
         outDtoBuffer[outOffset++] = (uint8_t)(startOdt + o);

         // Optional 4-byte microsecond timestamp
         if(hasTimestamp)
         {
            if((outOffset + 4) > maxLen) return outOffset;
            outDtoBuffer[outOffset++] = (uint8_t)(timestampUs & 0xFF);
            outDtoBuffer[outOffset++] = (uint8_t)((timestampUs >> 8) & 0xFF);
            outDtoBuffer[outOffset++] = (uint8_t)((timestampUs >> 16) & 0xFF);
            outDtoBuffer[outOffset++] = (uint8_t)((timestampUs >> 24) & 0xFF);
         }

         // Sample each configured entry in this ODT
         for(uint32_t e = 0; e < odt->entryCount; e++)
         {
            XcpOdtEntry* entry = &odt->entries[e];
            if(entry->length == 0) continue;

            if((outOffset + entry->length) > maxLen)
            {
               return outOffset;
            }

            uint8_t* src = xcp_stream_resolve_memory(server, entry->address, entry->extension, entry->length);
            if(src)
            {
               memcpy(outDtoBuffer + outOffset, src, entry->length);
            }
            else
            {
               memset(outDtoBuffer + outOffset, 0, entry->length);
            }
            outOffset += entry->length;
         }
      }
   }

   return outOffset;
}
