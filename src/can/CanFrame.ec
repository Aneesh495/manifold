// src/can/CanFrame.ec
// CAN 2.0B and CAN FD frame operations, formatting, and payload padding.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>

#include "types.eh"
#include "can.eh"
#include "ec_runtime.h"

void can_frame_init(CanFrame* frame, uint32_t id, bool isExtended, bool isFd)
{
   if(!frame) return;
   memset(frame, 0, sizeof(CanFrame));

   if(isExtended)
   {
      frame->arbitrationId = id & 0x1FFFFFFFU; // 29-bit mask
      frame->flags.isExtended = 1;
   }
   else
   {
      frame->arbitrationId = id & 0x7FFU;       // 11-bit mask
      frame->flags.isExtended = 0;
   }

   frame->flags.isFd = isFd ? 1 : 0;
   frame->flags.bitRateSwitch = isFd ? 1 : 0; // Default BRS active for CAN FD
   frame->dlc = 0;
   frame->payloadLength = 0;

   uint64_t nowUs = ec_get_time_us();
   frame->timestamp.seconds = nowUs / 1000000ULL;
   frame->timestamp.microseconds = (uint32_t)(nowUs % 1000000ULL);
}

bool can_frame_set_payload(CanFrame* frame, const uint8_t* payload, uint8_t len)
{
   if(!frame) return false;

   uint8_t maxLen = frame->flags.isFd ? CAN_FD_MAX_DATA_LEN : CAN_MAX_STANDARD_DLC;
   if(len > maxLen) return false;

   frame->dlc = can_fd_len_to_dlc(len);
   uint8_t paddedLen = can_fd_dlc_to_len(frame->dlc);

   if(len > 0 && payload)
   {
      memcpy(frame->data, payload, len);
   }

   // Standard AUTOSAR / ISO CAN FD padding with 0xCC for unused trailing bytes
   if(paddedLen > len)
   {
      memset(frame->data + len, 0xCC, paddedLen - len);
   }

   frame->payloadLength = paddedLen;
   return true;
}

// Formats a CAN/CAN-FD frame into standard candump string representation
int can_frame_to_candump(const CanFrame* frame, const char* interfaceName, char* outBuf, size_t bufSize)
{
   if(!frame || !outBuf || bufSize == 0) return 0;

   const char* iface = interfaceName ? interfaceName : "can0";
   char idStr[16];
   if(frame->flags.isExtended)
   {
      snprintf(idStr, sizeof(idStr), "%08X", frame->arbitrationId);
   }
   else
   {
      snprintf(idStr, sizeof(idStr), "%03X", frame->arbitrationId);
   }

   int written = 0;
   if(frame->flags.isFd)
   {
      // CAN FD candump format: <iface> <id> ## <flags> <data...>
      uint8_t flagsByte = (uint8_t)((frame->flags.bitRateSwitch ? 1 : 0) | (frame->flags.errorState ? 2 : 0));
      written += snprintf(outBuf + written, bufSize - written, "%-5s %s ## %X", iface, idStr, flagsByte);
      for(uint8_t i = 0; i < frame->payloadLength && (size_t)written < bufSize - 3; i++)
      {
         written += snprintf(outBuf + written, bufSize - written, " %02X", frame->data[i]);
      }
   }
   else
   {
      // Classical CAN format: <iface> <id>   [<dlc>] <data...>
      written += snprintf(outBuf + written, bufSize - written, "%-5s %-8s [%d]", iface, idStr, frame->dlc);
      for(uint8_t i = 0; i < frame->payloadLength && (size_t)written < bufSize - 3; i++)
      {
         written += snprintf(outBuf + written, bufSize - written, " %02X", frame->data[i]);
      }
   }

   return written;
}
