// src/xcp/XcpDaqAlloc.ec
// ASAM XCP Dynamic DAQ list, ODT, and ODT-entry allocation and pointer navigation.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "xcp.eh"
#include "ec_runtime.h"

// Allocates dynamic DAQ lists (ALLOC_DAQ 0xD7)
bool xcp_alloc_daq(XcpServer* server, uint16_t daqCount)
{
   if(!server || daqCount > XCP_MAX_DAQ_LISTS)
   {
      return false;
   }

   // Reset all DAQ lists
   for(uint32_t i = 0; i < XCP_MAX_DAQ_LISTS; i++)
   {
      memset(&server->daqLists[i], 0, sizeof(XcpDaqList));
   }

   server->daqCount = (uint8_t)daqCount;
   server->daqRunning = false;
   return true;
}

// Allocates Object Descriptor Tables (ODT) for a specific DAQ list (ALLOC_ODT 0xD6)
bool xcp_alloc_odt(XcpServer* server, uint16_t daqList, uint8_t odtCount)
{
   if(!server || daqList >= server->daqCount || odtCount > XCP_MAX_ODT_PER_DAQ)
   {
      return false;
   }

   XcpDaqList* list = &server->daqLists[daqList];
   for(uint32_t o = 0; o < XCP_MAX_ODT_PER_DAQ; o++)
   {
      memset(&list->odts[o], 0, sizeof(XcpOdt));
   }

   list->odtCount = odtCount;
   return true;
}

// Allocates ODT entries for a specific ODT within a DAQ list (ALLOC_ODT_ENTRY 0xD5)
bool xcp_alloc_odt_entry(XcpServer* server, uint16_t daqList, uint8_t odt, uint8_t odtEntries)
{
   if(!server || daqList >= server->daqCount)
   {
      return false;
   }

   XcpDaqList* list = &server->daqLists[daqList];
   if(odt >= list->odtCount || odtEntries > XCP_MAX_ENTRIES_PER_ODT)
   {
      return false;
   }

   XcpOdt* o = &list->odts[odt];
   memset(o->entries, 0, sizeof(o->entries));
   o->entryCount = odtEntries;

   return true;
}

// Sets the current DAQ list pointer for subsequent WRITE_DAQ commands (SET_DAQ_PTR 0xE2)
bool xcp_set_daq_ptr(XcpServer* server, uint16_t daqList, uint8_t odt, uint8_t odtEntry)
{
   if(!server || daqList >= server->daqCount)
   {
      return false;
   }

   XcpDaqList* list = &server->daqLists[daqList];
   if(odt >= list->odtCount)
   {
      return false;
   }

   XcpOdt* o = &list->odts[odt];
   if(odtEntry >= o->entryCount)
   {
      return false;
   }

   server->curDaqList = daqList;
   server->curOdt = odt;
   server->curOdtEntry = odtEntry;

   return true;
}

// Configures an ODT entry with target memory address, length, and extension (WRITE_DAQ 0xE1)
bool xcp_write_daq(XcpServer* server, uint8_t bitOffset, uint8_t size, uint8_t ext, uint32_t address)
{
   if(!server || server->curDaqList >= server->daqCount)
   {
      return false;
   }

   XcpDaqList* list = &server->daqLists[server->curDaqList];
   if(server->curOdt >= list->odtCount)
   {
      return false;
   }

   XcpOdt* o = &list->odts[server->curOdt];
   if(server->curOdtEntry >= o->entryCount)
   {
      return false;
   }

   XcpOdtEntry* entry = &o->entries[server->curOdtEntry];
   entry->bitOffset = bitOffset;
   entry->length    = size;
   entry->extension = ext;
   entry->address   = address;

   // ASAM specification post-increment: pointer advances to next entry within current ODT
   server->curOdtEntry++;

   return true;
}

// Configures transmission parameters and event channel mapping for a DAQ list (SET_DAQ_LIST_MODE 0xE0)
bool xcp_set_daq_list_mode(XcpServer* server, uint16_t daqList, uint8_t mode, uint16_t eventChannel, uint8_t prescaler, uint8_t priority)
{
   if(!server || daqList >= server->daqCount)
   {
      return false;
   }

   XcpDaqList* list = &server->daqLists[daqList];
   list->mode         = mode;
   list->eventChannel = eventChannel;
   list->prescaler    = (prescaler == 0) ? 1 : prescaler;
   list->priority     = priority;

   return true;
}

// Starts, stops, or selects a specific DAQ list (START_STOP_DAQ_LIST 0xDE)
bool xcp_start_stop_daq_list(XcpServer* server, uint8_t mode, uint16_t daqList)
{
   if(!server || daqList >= server->daqCount)
   {
      return false;
   }

   XcpDaqList* list = &server->daqLists[daqList];
   if(mode == 0x00) // Stop
   {
      list->isRunning = false;
   }
   else if(mode == 0x01) // Start
   {
      list->isRunning = true;
      server->daqRunning = true;
   }
   else if(mode == 0x02) // Select
   {
      list->isRunning = true;
   }
   else
   {
      return false;
   }

   return true;
}

// Synchronously starts or stops all configured DAQ lists (START_STOP_SYNCH 0xDD)
bool xcp_start_stop_synch(XcpServer* server, uint8_t mode)
{
   if(!server) return false;

   if(mode == 0x00) // Stop all
   {
      server->daqRunning = false;
      for(uint32_t i = 0; i < server->daqCount; i++)
      {
         server->daqLists[i].isRunning = false;
      }
   }
   else if(mode == 0x01) // Start all selected
   {
      server->daqRunning = true;
      for(uint32_t i = 0; i < server->daqCount; i++)
      {
         if(server->daqLists[i].isRunning)
         {
            server->daqRunning = true;
         }
      }
   }
   else
   {
      return false;
   }

   return true;
}
