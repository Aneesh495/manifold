// src/xcp/XcpProtocol.ec
// ASAM XCP Command Transfer Object (CTO) dispatching and standard protocol state machine.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "xcp.eh"
#include "ec_runtime.h"

#define XCP_MAX_CTO_SIZE 32
#define XCP_MAX_DTO_SIZE 64

// Initializes the XCP calibration and measurement server instance
void xcp_server_init(XcpServer* server)
{
   if(!server) return;

   memset(server, 0, sizeof(XcpServer));
   server->isConnected = false;
   server->currentMta = 0;
   server->mtaExtension = 0;
   server->ecuCalPage = 0; // Page 0: Flash default
   server->xcpCalPage = 1; // Page 1: RAM default for calibration tool

   // Seed default calibration map parameters
   for(uint32_t i = 0; i < XCP_CAL_PAGE_SIZE; i++)
   {
      server->flashCalPage[i] = (uint8_t)(i & 0xFF);
      server->ramCalPage[i]   = (uint8_t)(i & 0xFF);
   }

   server->daqCount = 0;
   server->daqRunning = false;
   server->curDaqList = 0;
   server->curOdt = 0;
   server->curOdtEntry = 0;
}

// Constructs an ASAM XCP Error Response packet (PID = 0xFE)
uint32_t xcp_build_error_response(uint8_t errCode, uint8_t* resp, uint32_t maxRespLen)
{
   if(!resp || maxRespLen < 2)
   {
      return 0;
   }
   resp[0] = XCP_PID_ERROR_RESPONSE;
   resp[1] = errCode;
   return 2;
}

// Top-level command processor for ASAM XCP Command Transfer Objects (CTO)
uint32_t xcp_process_command(XcpServer* server, const uint8_t* cmd, uint32_t cmdLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !cmd || !resp || cmdLen < 1 || maxRespLen < 2)
   {
      return 0;
   }

   uint8_t opcode = cmd[0];

   // SYNCH command is permitted at any time, even prior to CONNECT
   if(opcode == XCP_CMD_SYNCH)
   {
      return xcp_build_error_response(XCP_ERR_CMD_SYNCH, resp, maxRespLen);
   }

   // All other commands except CONNECT require an active session
   if(!server->isConnected && opcode != XCP_CMD_CONNECT)
   {
      return xcp_build_error_response(XCP_ERR_CMD_UNKNOWN, resp, maxRespLen);
   }

   switch(opcode)
   {
      case XCP_CMD_CONNECT:
      {
         server->isConnected = true;
         resp[0] = XCP_PID_CMD_RESPONSE;
         resp[1] = 0x15; // Resources: CAL/PAG (0x01) | DAQ (0x04) | PGM (0x10)
         resp[2] = 0x00; // Comm Mode Basic (byte order Intel standard)
         resp[3] = XCP_MAX_CTO_SIZE;
         resp[4] = (uint8_t)(XCP_MAX_DTO_SIZE & 0xFF);
         resp[5] = (uint8_t)((XCP_MAX_DTO_SIZE >> 8) & 0xFF);
         resp[6] = 0x01; // XCP Protocol Layer Version 1.0
         resp[7] = 0x01; // Transport Layer Version 1.0
         return 8;
      }

      case XCP_CMD_DISCONNECT:
      {
         server->isConnected = false;
         server->daqRunning = false;
         for(uint32_t i = 0; i < server->daqCount; i++)
         {
            server->daqLists[i].isRunning = false;
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_GET_STATUS:
      {
         resp[0] = XCP_PID_CMD_RESPONSE;
         resp[1] = (uint8_t)(server->daqRunning ? 0x01 : 0x00); // Current session status (DAQ running)
         resp[2] = 0x00; // Resource protection status (none locked)
         resp[3] = 0x00; // Reserved
         resp[4] = 0x00; // Session configuration ID low
         resp[5] = 0x00; // Session configuration ID high
         return 6;
      }

      case XCP_CMD_GET_COMM_MODE_INFO:
      {
         resp[0] = XCP_PID_CMD_RESPONSE;
         resp[1] = 0x00; // Comm Mode Optional
         resp[2] = 0x08; // Maximum block size
         resp[3] = 0x00; // Minimum separation time (STmin)
         resp[4] = 0x00; // Queue size
         resp[5] = 0x01; // XCP Driver Version
         return 6;
      }

      case XCP_CMD_GET_ID:
      {
         const char* idStr = "MANIFOLD_IVN_XCP_GATEWAY";
         uint32_t idLen = (uint32_t)strlen(idStr);
         resp[0] = XCP_PID_CMD_RESPONSE;
         resp[1] = 0x00; // Mode: ASCII text
         resp[2] = 0x00; // Reserved
         resp[3] = 0x00; // Reserved
         resp[4] = (uint8_t)(idLen & 0xFF);
         resp[5] = (uint8_t)((idLen >> 8) & 0xFF);
         resp[6] = 0x00;
         resp[7] = 0x00;
         if(maxRespLen >= (8 + idLen))
         {
            memcpy(resp + 8, idStr, idLen);
            return 8 + idLen;
         }
         return 8;
      }

      case XCP_CMD_SET_MTA:
      {
         if(cmdLen < 8) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t ext = cmd[3];
         uint32_t addr = (uint32_t)cmd[4] | ((uint32_t)cmd[5] << 8) |
                         ((uint32_t)cmd[6] << 16) | ((uint32_t)cmd[7] << 24);
         if(!xcp_set_mta(server, addr, ext))
         {
            return xcp_build_error_response(XCP_ERR_OUT_OF_RANGE, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_UPLOAD:
      {
         if(cmdLen < 2) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t numBytes = cmd[1];
         return xcp_upload(server, numBytes, resp, maxRespLen);
      }

      case XCP_CMD_SHORT_UPLOAD:
      {
         if(cmdLen < 8) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t numBytes = cmd[1];
         uint8_t ext = cmd[3];
         uint32_t addr = (uint32_t)cmd[4] | ((uint32_t)cmd[5] << 8) |
                         ((uint32_t)cmd[6] << 16) | ((uint32_t)cmd[7] << 24);
         return xcp_short_upload(server, addr, ext, numBytes, resp, maxRespLen);
      }

      case XCP_CMD_DOWNLOAD:
      {
         if(cmdLen < 2) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t numBytes = cmd[1];
         if(cmdLen < (uint32_t)(2 + numBytes))
         {
            return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         }
         if(!xcp_download(server, cmd + 2, numBytes))
         {
            return xcp_build_error_response(XCP_ERR_ACCESS_DENIED, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_SET_CAL_PAGE:
      {
         if(cmdLen < 4) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t mode = cmd[1];
         uint8_t seg  = cmd[2];
         uint8_t page = cmd[3];
         if(!xcp_set_cal_page(server, seg, page, mode))
         {
            return xcp_build_error_response(XCP_ERR_PAGE_NOT_VALID, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_GET_CAL_PAGE:
      {
         if(cmdLen < 3) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t mode = cmd[1];
         uint8_t seg  = cmd[2];
         uint8_t page = xcp_get_cal_page(server, seg, mode);
         if(page == 0xFF)
         {
            return xcp_build_error_response(XCP_ERR_SEGMENT_NOT_VALID, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         resp[1] = 0x00; // Reserved
         resp[2] = 0x00; // Reserved
         resp[3] = page;
         return 4;
      }

      case XCP_CMD_COPY_CAL_PAGE:
      {
         if(cmdLen < 5) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t srcSeg  = cmd[1];
         uint8_t srcPage = cmd[2];
         uint8_t dstSeg  = cmd[3];
         uint8_t dstPage = cmd[4];
         if(!xcp_copy_cal_page(server, srcSeg, srcPage, dstSeg, dstPage))
         {
            return xcp_build_error_response(XCP_ERR_PAGE_NOT_VALID, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_BUILD_CHECKSUM:
      {
         if(cmdLen < 8) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint32_t blockSize = (uint32_t)cmd[4] | ((uint32_t)cmd[5] << 8) |
                              ((uint32_t)cmd[6] << 16) | ((uint32_t)cmd[7] << 24);
         return xcp_build_checksum(server, blockSize, resp, maxRespLen);
      }

      case XCP_CMD_ALLOC_DAQ:
      {
         if(cmdLen < 4) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint16_t daqCount = (uint16_t)cmd[2] | ((uint16_t)cmd[3] << 8);
         if(!xcp_alloc_daq(server, daqCount))
         {
            return xcp_build_error_response(XCP_ERR_MEMORY_OVERFLOW, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_ALLOC_ODT:
      {
         if(cmdLen < 4) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint16_t daqList = (uint16_t)cmd[2] | ((uint16_t)cmd[3] << 8);
         uint8_t odtCount = cmd[1]; // ODT count
         if(!xcp_alloc_odt(server, daqList, odtCount))
         {
            return xcp_build_error_response(XCP_ERR_MEMORY_OVERFLOW, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_ALLOC_ODT_ENTRY:
      {
         if(cmdLen < 5) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint16_t daqList = (uint16_t)cmd[2] | ((uint16_t)cmd[3] << 8);
         uint8_t odt = cmd[4];
         uint8_t odtEntries = cmd[1];
         if(!xcp_alloc_odt_entry(server, daqList, odt, odtEntries))
         {
            return xcp_build_error_response(XCP_ERR_MEMORY_OVERFLOW, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_SET_DAQ_PTR:
      {
         if(cmdLen < 5) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint16_t daqList = (uint16_t)cmd[2] | ((uint16_t)cmd[3] << 8);
         uint8_t odt = cmd[4];
         uint8_t odtEntry = (cmdLen >= 6) ? cmd[5] : 0;
         if(!xcp_set_daq_ptr(server, daqList, odt, odtEntry))
         {
            return xcp_build_error_response(XCP_ERR_OUT_OF_RANGE, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_WRITE_DAQ:
      {
         if(cmdLen < 8) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t bitOffset = cmd[1];
         uint8_t size = cmd[2];
         uint8_t ext = cmd[3];
         uint32_t addr = (uint32_t)cmd[4] | ((uint32_t)cmd[5] << 8) |
                         ((uint32_t)cmd[6] << 16) | ((uint32_t)cmd[7] << 24);
         if(!xcp_write_daq(server, bitOffset, size, ext, addr))
         {
            return xcp_build_error_response(XCP_ERR_DAQ_CONFIG, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_SET_DAQ_LIST_MODE:
      {
         if(cmdLen < 8) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t mode = cmd[1];
         uint16_t daqList = (uint16_t)cmd[2] | ((uint16_t)cmd[3] << 8);
         uint16_t eventChannel = (uint16_t)cmd[4] | ((uint16_t)cmd[5] << 8);
         uint8_t prescaler = cmd[6];
         uint8_t priority = cmd[7];
         if(!xcp_set_daq_list_mode(server, daqList, mode, eventChannel, prescaler, priority))
         {
            return xcp_build_error_response(XCP_ERR_OUT_OF_RANGE, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      case XCP_CMD_START_STOP_DAQ_LIST:
      {
         if(cmdLen < 4) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t mode = cmd[1];
         uint16_t daqList = (uint16_t)cmd[2] | ((uint16_t)cmd[3] << 8);
         if(!xcp_start_stop_daq_list(server, mode, daqList))
         {
            return xcp_build_error_response(XCP_ERR_OUT_OF_RANGE, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         resp[1] = 0x00; // First PID
         return 2;
      }

      case XCP_CMD_START_STOP_SYNCH:
      {
         if(cmdLen < 2) return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         uint8_t mode = cmd[1];
         if(!xcp_start_stop_synch(server, mode))
         {
            return xcp_build_error_response(XCP_ERR_CMD_SYNTAX, resp, maxRespLen);
         }
         resp[0] = XCP_PID_CMD_RESPONSE;
         return 1;
      }

      default:
         return xcp_build_error_response(XCP_ERR_CMD_UNKNOWN, resp, maxRespLen);
   }
}
