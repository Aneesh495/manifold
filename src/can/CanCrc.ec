// src/can/CanCrc.ec
// CAN frame CRC evaluation and verification wrappers in eC.

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"
#include "can.eh"
#include "ec_runtime.h"

// Computes the appropriate standard CRC for a given CAN or CAN FD frame
uint32_t can_frame_compute_crc(CanFrame* frame, uint8_t stuffCount)
{
   if(!frame) return 0;

   if(!frame->flags.isFd)
   {
      // Classical CAN uses CRC-15
      frame->crc = can_crc15(frame->data, frame->payloadLength);
   }
   else if(frame->payloadLength <= 16)
   {
      // CAN FD with <= 16 bytes payload uses CRC-17
      frame->crc = can_fd_crc17(frame->data, frame->payloadLength, stuffCount);
   }
   else
   {
      // CAN FD with > 16 bytes payload uses CRC-21
      frame->crc = can_fd_crc21(frame->data, frame->payloadLength, stuffCount);
   }

   return frame->crc;
}

// Verifies a received frame CRC against an expected CRC value
bool can_frame_verify_crc(const CanFrame* frame, uint8_t stuffCount, uint32_t expectedCrc)
{
   if(!frame) return false;

   uint32_t computed = 0;
   if(!frame->flags.isFd)
   {
      computed = can_crc15(frame->data, frame->payloadLength);
   }
   else if(frame->payloadLength <= 16)
   {
      computed = can_fd_crc17(frame->data, frame->payloadLength, stuffCount);
   }
   else
   {
      computed = can_fd_crc21(frame->data, frame->payloadLength, stuffCount);
   }

   return (computed == expectedCrc);
}
