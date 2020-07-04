// src/uds/UdsTransferService.ec
// ISO 14229-1 Service 0x34: RequestDownload, Service 0x36: TransferData,
// and Service 0x37: RequestTransferExit for firmware reprogramming.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations from UdsPdu.ec
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen);

#define UDS_MAX_BLOCK_LENGTH 1024 // Maximum block size per TransferData PDU

// Simulated Flash Memory Buffer (64 KB)
#define SIMULATED_FLASH_SIZE 65536
static uint8_t g_simulatedFlash[SIMULATED_FLASH_SIZE];

uint8_t* uds_get_flash_buffer(void)
{
   return g_simulatedFlash;
}

// Handles Service 0x34: RequestDownload
uint32_t uds_handle_request_download(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp || reqLen < 6)
   {
      return uds_build_negative_response(UDS_SID_REQUEST_DOWNLOAD,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   // RequestDownload requires Programming Session and Security Access
   if(server->currentSession != DIAG_SESSION_PROGRAMMING || server->security.currentLevel < 1)
   {
      return uds_build_negative_response(UDS_SID_REQUEST_DOWNLOAD,
                                         NRC_SECURITY_ACCESS_DENIED,
                                         resp, maxRespLen);
   }

   // Byte 1: dataFormatIdentifier (0x00: uncompressed, unencrypted)
   // Byte 2: addressAndLengthFormatIdentifier (e.g. 0x44: 4 bytes address, 4 bytes length)
   uint8_t addrLenFormat = req[2];
   uint8_t addrBytes = addrLenFormat & 0x0F;
   uint8_t lenBytes = (addrLenFormat >> 4) & 0x0F;

   if(reqLen < 3 + addrBytes + lenBytes)
   {
      return uds_build_negative_response(UDS_SID_REQUEST_DOWNLOAD,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   uint32_t memAddress = 0;
   for(int i = 0; i < addrBytes; i++)
   {
      memAddress = (memAddress << 8) | req[3 + i];
   }

   uint32_t memSize = 0;
   for(int i = 0; i < lenBytes; i++)
   {
      memSize = (memSize << 8) | req[3 + addrBytes + i];
   }

   if(memSize == 0 || memSize > SIMULATED_FLASH_SIZE || memAddress + memSize > SIMULATED_FLASH_SIZE)
   {
      return uds_build_negative_response(UDS_SID_REQUEST_DOWNLOAD,
                                         NRC_REQUEST_OUT_OF_RANGE,
                                         resp, maxRespLen);
   }

   server->activeTransferAddress = memAddress;
   server->activeTransferSize = memSize;
   server->transferredBytes = 0;
   server->nextBlockSequence = 1; // Initial block sequence counter starts at 1
   server->transferActive = true;

   if(maxRespLen < 4) return 0;
   resp[0] = UDS_SID_REQUEST_DOWNLOAD + 0x40; // 0x74
   resp[1] = 0x20; // 2-byte maxNumberOfBlockLength format
   resp[2] = (uint8_t)((UDS_MAX_BLOCK_LENGTH >> 8) & 0xFF);
   resp[3] = (uint8_t)(UDS_MAX_BLOCK_LENGTH & 0xFF);
   return 4;
}

// Handles Service 0x36: TransferData
uint32_t uds_handle_transfer_data(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   if(!server || !req || !resp || reqLen < 2)
   {
      return uds_build_negative_response(UDS_SID_TRANSFER_DATA,
                                         NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT,
                                         resp, maxRespLen);
   }

   if(!server->transferActive)
   {
      return uds_build_negative_response(UDS_SID_TRANSFER_DATA,
                                         NRC_REQUEST_SEQUENCE_ERROR,
                                         resp, maxRespLen);
   }

   uint8_t bsc = req[1];
   if(bsc != server->nextBlockSequence)
   {
      return uds_build_negative_response(UDS_SID_TRANSFER_DATA,
                                         NRC_WRONG_BLOCK_SEQUENCE_COUNTER,
                                         resp, maxRespLen);
   }

   uint32_t chunkLen = reqLen - 2;
   if(server->transferredBytes + chunkLen > server->activeTransferSize)
   {
      return uds_build_negative_response(UDS_SID_TRANSFER_DATA,
                                         NRC_REQUEST_OUT_OF_RANGE,
                                         resp, maxRespLen);
   }

   // Write data chunk into simulated flash memory
   memcpy(g_simulatedFlash + server->activeTransferAddress + server->transferredBytes,
          req + 2, chunkLen);
   server->transferredBytes += chunkLen;

   // Block sequence counter rolls over after 255 back to 0 per ISO 14229-1
   server->nextBlockSequence = (uint8_t)(server->nextBlockSequence + 1);

   if(maxRespLen < 2) return 0;
   resp[0] = UDS_SID_TRANSFER_DATA + 0x40; // 0x76
   resp[1] = bsc;
   return 2;
}

// Handles Service 0x37: RequestTransferExit
uint32_t uds_handle_transfer_exit(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t maxRespLen)
{
   (void)req;
   (void)reqLen;
   if(!server || !resp) return 0;

   if(!server->transferActive)
   {
      return uds_build_negative_response(UDS_SID_REQUEST_TRANSFER_EXIT,
                                         NRC_REQUEST_SEQUENCE_ERROR,
                                         resp, maxRespLen);
   }

   if(server->transferredBytes != server->activeTransferSize)
   {
      return uds_build_negative_response(UDS_SID_REQUEST_TRANSFER_EXIT,
                                         NRC_REQUEST_OUT_OF_RANGE,
                                         resp, maxRespLen);
   }

   server->transferActive = false;

   if(maxRespLen < 1) return 0;
   resp[0] = UDS_SID_REQUEST_TRANSFER_EXIT + 0x40; // 0x77
   return 1;
}
