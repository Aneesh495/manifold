// src/isotp/IsoTpRx.ec
// ISO 15765-2 frame reassembly, sequence checking, and message completion engine.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "ec_runtime.h"

// Forward declarations from IsoTpFrame.ec and IsoTpFlowControl.ec
typedef struct IsoTpPci IsoTpPci;
bool isotp_parse_pci(const uint8_t* data, uint8_t len, bool isFd, IsoTpPci* outPci);
bool isotp_fc_generate(const IsoTpChannel* chan, IsoTpFlowStatus status, CanFrame* outFrame);
bool isotp_fc_process(IsoTpChannel* chan, IsoTpFlowStatus fs, uint8_t bs, uint8_t stMin);

// Ingests an incoming CAN frame into the ISO-TP receiver state machine
// Returns true when a complete reassembled message is ready in outMsg
bool isotp_rx_frame(IsoTpChannel* chan, const CanFrame* frame, uint8_t* outMsg, uint32_t* outLen, CanFrame* outFcFrame, bool* fcNeeded)
{
   if(!chan || !frame || !outMsg || !outLen || !outFcFrame || !fcNeeded) return false;
   *fcNeeded = false;
   *outLen = 0;

   // Check CAN identifier match
   if(frame->arbitrationId != chan->config.rxId)
   {
      return false; // Not addressed to this ISO-TP channel
   }

   IsoTpPci pci;
   if(!isotp_parse_pci(frame->data, frame->payloadLength, frame->flags.isFd != 0, &pci))
   {
      return false; // Malformed N_PCI
   }

   switch(pci.type)
   {
      case ISOTP_FRAME_SINGLE:
      {
         if(pci.dataLength > ISOTP_MAX_MSG_SIZE) return false;
         memcpy(outMsg, frame->data + pci.headerLength, pci.dataLength);
         *outLen = pci.dataLength;
         chan->state = ISOTP_STATE_IDLE;
         return true; // Single frame message complete!
      }

      case ISOTP_FRAME_FIRST:
      {
         if(pci.dataLength > ISOTP_MAX_MSG_SIZE)
         {
            // Message exceeds buffer capacity: send Flow Control Overflow
            isotp_fc_generate(chan, ISOTP_FS_OVERFLOW, outFcFrame);
            *fcNeeded = true;
            chan->state = ISOTP_STATE_ERROR;
            return false;
         }

         chan->rxExpectedLen = pci.dataLength;
         uint8_t initialChunk = frame->payloadLength - pci.headerLength;
         memcpy(chan->rxBuffer, frame->data + pci.headerLength, initialChunk);
         chan->rxReceivedLen = initialChunk;
         chan->rxSequenceNumber = 1; // First CF must have SN = 1
         chan->state = ISOTP_STATE_RECEIVING;

         // Generate Flow Control CTS
         isotp_fc_generate(chan, ISOTP_FS_CTS, outFcFrame);
         *fcNeeded = true;
         return false; // In progress
      }

      case ISOTP_FRAME_CONSECUTIVE:
      {
         if(chan->state != ISOTP_STATE_RECEIVING)
         {
            return false; // Spurious Consecutive Frame
         }

         if(pci.sequenceNumber != chan->rxSequenceNumber)
         {
            chan->state = ISOTP_STATE_ERROR;
            return false; // Sequence number error
         }

         uint32_t remaining = chan->rxExpectedLen - chan->rxReceivedLen;
         uint32_t chunk = pci.dataLength;
         if(chunk > remaining) chunk = remaining;

         memcpy(chan->rxBuffer + chan->rxReceivedLen, frame->data + pci.headerLength, chunk);
         chan->rxReceivedLen += chunk;
         chan->rxSequenceNumber = (chan->rxSequenceNumber + 1) & 0x0F;

         if(chan->rxReceivedLen >= chan->rxExpectedLen)
         {
            // Message reassembly complete!
            memcpy(outMsg, chan->rxBuffer, chan->rxExpectedLen);
            *outLen = chan->rxExpectedLen;
            chan->state = ISOTP_STATE_IDLE;
            return true;
         }
         return false; // Still receiving
      }

      case ISOTP_FRAME_FLOW_CONTROL:
      {
         // Process Flow Control at transmitter
         return isotp_fc_process(chan, pci.flowStatus, pci.blockSize, pci.separationTime);
      }

      default:
         return false;
   }
}
