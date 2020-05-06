// src/isotp/IsoTpFlowControl.ec
// ISO 15765-2 Flow Control (FC) generation, processing, and rate adaptation.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "ec_runtime.h"

// Forward declaration from IsoTpFrame.ec
uint8_t isotp_encode_flow_control(uint8_t* outData, uint8_t maxLen, IsoTpFlowStatus fs, uint8_t bs, uint8_t stMin);

// Generates a Flow Control frame to send back to the transmitter
bool isotp_fc_generate(const IsoTpChannel* chan, IsoTpFlowStatus status, CanFrame* outFrame)
{
   if(!chan || !outFrame) return false;

   can_frame_init(outFrame, chan->config.txId, chan->config.isExtended, chan->config.isFd);
   uint8_t payload[8] = { 0 };

   uint8_t bs = chan->config.blockSize;
   uint8_t stMin = chan->config.separationTime;

   uint8_t encLen = isotp_encode_flow_control(payload, sizeof(payload), status, bs, stMin);
   can_frame_set_payload(outFrame, payload, encLen);
   return true;
}

// Processes a received Flow Control frame at the transmitter
bool isotp_fc_process(IsoTpChannel* chan, IsoTpFlowStatus fs, uint8_t bs, uint8_t stMin)
{
   if(!chan) return false;

   if(chan->state != ISOTP_STATE_WAIT_FC)
   {
      return false; // Unexpected Flow Control
   }

   switch(fs)
   {
      case ISOTP_FS_CTS:
         chan->txBlockSize = bs;
         chan->txSeparationTime = stMin;
         chan->state = ISOTP_STATE_SENDING; // Resume sending consecutive frames
         return true;

      case ISOTP_FS_WAIT:
         // Wait requested by receiver: remain in WAIT_FC state, reset timer
         return true;

      case ISOTP_FS_OVERFLOW:
         chan->state = ISOTP_STATE_ERROR;
         return false;

      default:
         chan->state = ISOTP_STATE_ERROR;
         return false;
   }
}
