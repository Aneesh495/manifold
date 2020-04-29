// src/isotp/IsoTpFrame.ec
// ISO 15765-2 Protocol Control Information (N_PCI) parsing and serialization.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "ec_runtime.h"

// Parsed N_PCI structure
typedef struct IsoTpPci
{
   IsoTpFrameType type;
   uint32_t dataLength;      // For SF and FF
   uint8_t sequenceNumber;   // For CF (0 to 15)
   IsoTpFlowStatus flowStatus; // For FC
   uint8_t blockSize;        // For FC
   uint8_t separationTime;   // For FC
   uint8_t headerLength;     // Number of bytes consumed by N_PCI
} IsoTpPci;

// Parses N_PCI header from incoming CAN frame data
bool isotp_parse_pci(const uint8_t* data, uint8_t len, bool isFd, IsoTpPci* outPci)
{
   if(!data || len == 0 || !outPci) return false;
   memset(outPci, 0, sizeof(IsoTpPci));

   uint8_t pciType = (data[0] >> 4) & 0x0F;

   switch(pciType)
   {
      case ISOTP_FRAME_SINGLE:
      {
         outPci->type = ISOTP_FRAME_SINGLE;
         uint8_t sfDl = data[0] & 0x0F;
         if(sfDl > 0)
         {
            // Standard CAN Single Frame (1 to 7 bytes)
            outPci->dataLength = sfDl;
            outPci->headerLength = 1;
         }
         else if(isFd && len >= 2)
         {
            // CAN FD large Single Frame (8 to 62 bytes, indicated by data[0] == 0)
            outPci->dataLength = data[1];
            outPci->headerLength = 2;
         }
         else
         {
            return false;
         }
         return (outPci->headerLength + outPci->dataLength <= len);
      }

      case ISOTP_FRAME_FIRST:
      {
         outPci->type = ISOTP_FRAME_FIRST;
         if(len < 2) return false;

         uint16_t ffDl = (uint16_t)(((data[0] & 0x0F) << 8) | data[1]);
         if(ffDl > 0)
         {
            outPci->dataLength = ffDl;
            outPci->headerLength = 2;
         }
         else if(len >= 6)
         {
            // Extended 32-bit data length (ISO 15765-2:2016 for messages > 4095 bytes)
            outPci->dataLength = ((uint32_t)data[2] << 24) |
                                 ((uint32_t)data[3] << 16) |
                                 ((uint32_t)data[4] << 8)  |
                                 ((uint32_t)data[5]);
            outPci->headerLength = 6;
         }
         else
         {
            return false;
         }
         return true;
      }

      case ISOTP_FRAME_CONSECUTIVE:
      {
         outPci->type = ISOTP_FRAME_CONSECUTIVE;
         outPci->sequenceNumber = data[0] & 0x0F;
         outPci->headerLength = 1;
         outPci->dataLength = (len > 1) ? (uint32_t)(len - 1) : 0;
         return true;
      }

      case ISOTP_FRAME_FLOW_CONTROL:
      {
         outPci->type = ISOTP_FRAME_FLOW_CONTROL;
         if(len < 3) return false;

         outPci->flowStatus = (IsoTpFlowStatus)(data[0] & 0x0F);
         outPci->blockSize = data[1];
         outPci->separationTime = data[2];
         outPci->headerLength = 3;
         return true;
      }

      default:
         return false;
   }
}

// Encodes Single Frame N_PCI into CAN frame data buffer
uint8_t isotp_encode_single_frame(uint8_t* outData, uint8_t maxLen, const uint8_t* payload, uint8_t payloadLen, bool isFd)
{
   if(!outData || !payload || payloadLen == 0 || maxLen < payloadLen + 1) return 0;

   if(!isFd || payloadLen <= 7)
   {
      // Standard Single Frame
      outData[0] = (uint8_t)((ISOTP_FRAME_SINGLE << 4) | (payloadLen & 0x0F));
      memcpy(outData + 1, payload, payloadLen);
      return payloadLen + 1;
   }
   else
   {
      // CAN FD large Single Frame
      if(maxLen < payloadLen + 2) return 0;
      outData[0] = 0x00;
      outData[1] = payloadLen;
      memcpy(outData + 2, payload, payloadLen);
      return payloadLen + 2;
   }
}

// Encodes First Frame N_PCI
uint8_t isotp_encode_first_frame(uint8_t* outData, uint8_t maxLen, uint32_t totalLength, const uint8_t* chunk, uint8_t chunkLen)
{
   if(!outData || !chunk || maxLen < 2 + chunkLen) return 0;

   if(totalLength <= 4095)
   {
      outData[0] = (uint8_t)((ISOTP_FRAME_FIRST << 4) | ((totalLength >> 8) & 0x0F));
      outData[1] = (uint8_t)(totalLength & 0xFF);
      memcpy(outData + 2, chunk, chunkLen);
      return 2 + chunkLen;
   }
   else
   {
      // 32-bit extended length
      if(maxLen < 6 + chunkLen) return 0;
      outData[0] = (uint8_t)(ISOTP_FRAME_FIRST << 4);
      outData[1] = 0x00;
      outData[2] = (uint8_t)((totalLength >> 24) & 0xFF);
      outData[3] = (uint8_t)((totalLength >> 16) & 0xFF);
      outData[4] = (uint8_t)((totalLength >> 8) & 0xFF);
      outData[5] = (uint8_t)(totalLength & 0xFF);
      memcpy(outData + 6, chunk, chunkLen);
      return 6 + chunkLen;
   }
}

// Encodes Consecutive Frame N_PCI
uint8_t isotp_encode_consecutive_frame(uint8_t* outData, uint8_t maxLen, uint8_t sn, const uint8_t* chunk, uint8_t chunkLen)
{
   if(!outData || !chunk || maxLen < 1 + chunkLen) return 0;

   outData[0] = (uint8_t)((ISOTP_FRAME_CONSECUTIVE << 4) | (sn & 0x0F));
   memcpy(outData + 1, chunk, chunkLen);
   return 1 + chunkLen;
}

// Encodes Flow Control Frame N_PCI
uint8_t isotp_encode_flow_control(uint8_t* outData, uint8_t maxLen, IsoTpFlowStatus fs, uint8_t bs, uint8_t stMin)
{
   if(!outData || maxLen < 3) return 0;

   outData[0] = (uint8_t)((ISOTP_FRAME_FLOW_CONTROL << 4) | ((uint8_t)fs & 0x0F));
   outData[1] = bs;
   outData[2] = stMin;
   return 3;
}
