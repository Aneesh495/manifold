// src/xcp/XcpCalPage.ec
// ASAM XCP calibration page switching, memory mirroring, and block checksumming.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "xcp.eh"
#include "ec_runtime.h"

#define XCP_CHECKSUM_TYPE_ADD_14 0x01

// Sets the active calibration page for ECU execution and/or XCP tool access (SET_CAL_PAGE 0xEB)
bool xcp_set_cal_page(XcpServer* server, uint8_t segment, uint8_t page, uint8_t mode)
{
   if(!server || segment != 0 || page > 1)
   {
      return false;
   }

   // Bit 0: Configure ECU access page
   if(mode & 0x01)
   {
      server->ecuCalPage = page;
   }

   // Bit 1: Configure XCP tool access page
   if(mode & 0x02)
   {
      server->xcpCalPage = page;
   }

   return true;
}

// Queries the currently active calibration page for ECU or XCP tool access (GET_CAL_PAGE 0xEA)
uint8_t xcp_get_cal_page(const XcpServer* server, uint8_t segment, uint8_t mode)
{
   if(!server || segment != 0)
   {
      return 0xFF; // Invalid segment
   }

   if(mode & 0x01)
   {
      return server->ecuCalPage;
   }
   else if(mode & 0x02)
   {
      return server->xcpCalPage;
   }

   return 0xFF;
}

// Copies calibration parameters from source page to destination page (COPY_CAL_PAGE 0xE4)
bool xcp_copy_cal_page(XcpServer* server, uint8_t srcSeg, uint8_t srcPage, uint8_t dstSeg, uint8_t dstPage)
{
   if(!server || srcSeg != 0 || dstSeg != 0 || srcPage > 1 || dstPage > 1)
   {
      return false;
   }

   // Flash reference page (page 0) cannot be overwritten
   if(dstPage == 0)
   {
      return false;
   }

   const uint8_t* src = (srcPage == 0) ? server->flashCalPage : server->ramCalPage;
   uint8_t* dst       = server->ramCalPage;

   memcpy(dst, src, XCP_CAL_PAGE_SIZE);
   return true;
}

// Calculates block checksum over active memory starting from current MTA (BUILD_CHECKSUM 0xF3)
uint32_t xcp_build_checksum(XcpServer* server, uint32_t blockSize, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !resp || maxRespLen < 8)
   {
      return 0;
   }

   if((server->currentMta + blockSize) > XCP_CAL_PAGE_SIZE)
   {
      return xcp_build_error_response(XCP_ERR_OUT_OF_RANGE, resp, maxRespLen);
   }

   const uint8_t* page = (server->xcpCalPage == 0) ? server->flashCalPage : server->ramCalPage;
   uint32_t sum = 0;

   for(uint32_t i = 0; i < blockSize; i++)
   {
      sum += page[server->currentMta + i];
   }

   resp[0] = XCP_PID_CMD_RESPONSE;
   resp[1] = XCP_CHECKSUM_TYPE_ADD_14;
   resp[2] = 0x00; // Reserved
   resp[3] = 0x00; // Reserved
   resp[4] = (uint8_t)(sum & 0xFF);
   resp[5] = (uint8_t)((sum >> 8) & 0xFF);
   resp[6] = (uint8_t)((sum >> 16) & 0xFF);
   resp[7] = (uint8_t)((sum >> 24) & 0xFF);

   return 8;
}
