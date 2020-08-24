// src/xcp/XcpMemory.ec
// ASAM XCP Memory Transfer Address (MTA) navigation, upload, and download services.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "xcp.eh"
#include "ec_runtime.h"

// Simulated Live Vehicle Telemetry memory segment (Extension 1)
static uint8_t g_telemetryRam[1024];

void xcp_memory_set_telemetry(uint32_t offset, const void* data, uint32_t len)
{
   if(offset + len <= sizeof(g_telemetryRam))
   {
      memcpy(g_telemetryRam + offset, data, len);
   }
}

// Sets the current Memory Transfer Address (MTA) and Address Extension
bool xcp_set_mta(XcpServer* server, uint32_t address, uint8_t extension)
{
   if(!server) return false;
   server->currentMta   = address;
   server->mtaExtension = extension;
   return true;
}

// Helper to resolve a pointer to memory given address and extension
static uint8_t* xcp_resolve_memory(XcpServer* server, uint32_t addr, uint8_t ext, uint32_t len, bool isWrite)
{
   if(!server) return NULL;

   // Extension 0: Calibration Page Segment
   if(ext == 0x00)
   {
      if(addr + len > XCP_CAL_PAGE_SIZE)
      {
         return NULL;
      }

      if(server->xcpCalPage == 0) // Flash Reference Page
      {
         if(isWrite)
         {
            return NULL; // Flash reference page is read-only
         }
         return server->flashCalPage + addr;
      }
      else // RAM Working Page
      {
         return server->ramCalPage + addr;
      }
   }
   // Extension 1: Real-time System Telemetry Segment
   else if(ext == 0x01)
   {
      if(addr + len > sizeof(g_telemetryRam))
      {
         return NULL;
      }
      return g_telemetryRam + addr;
   }

   return NULL;
}

// Handles XCP UPLOAD command: reads numBytes from current MTA and advances pointer
uint32_t xcp_upload(XcpServer* server, uint8_t numBytes, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !resp || maxRespLen < (uint32_t)(1 + numBytes))
   {
      return 0;
   }

   uint8_t* src = xcp_resolve_memory(server, server->currentMta, server->mtaExtension, numBytes, false);
   if(!src)
   {
      return xcp_build_error_response(XCP_ERR_ACCESS_DENIED, resp, maxRespLen);
   }

   resp[0] = XCP_PID_CMD_RESPONSE;
   memcpy(resp + 1, src, numBytes);
   server->currentMta += numBytes;

   return 1 + numBytes;
}

// Handles XCP SHORT_UPLOAD command: sets MTA and immediately uploads data in a single round-trip
uint32_t xcp_short_upload(XcpServer* server, uint32_t address, uint8_t extension, uint8_t numBytes, uint8_t* resp, uint32_t maxRespLen)
{
   if(!xcp_set_mta(server, address, extension))
   {
      return xcp_build_error_response(XCP_ERR_OUT_OF_RANGE, resp, maxRespLen);
   }
   return xcp_upload(server, numBytes, resp, maxRespLen);
}

// Handles XCP DOWNLOAD command: writes numBytes to current MTA and advances pointer
bool xcp_download(XcpServer* server, const uint8_t* data, uint8_t numBytes)
{
   if(!server || !data) return false;

   uint8_t* dst = xcp_resolve_memory(server, server->currentMta, server->mtaExtension, numBytes, true);
   if(!dst)
   {
      return false; // Access denied or write protected
   }

   memcpy(dst, data, numBytes);
   server->currentMta += numBytes;

   return true;
}
