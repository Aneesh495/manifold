// src/isotp/IsoTpTx.ec
// ISO 15765-2 transmit segmentation and Consecutive Frame (CF) pacing state machine.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "ec_runtime.h"

// Forward declaration from IsoTpFrame.ec
uint8_t isotp_encode_single_frame(uint8_t* outData, uint8_t maxLen, const uint8_t* payload, uint8_t payloadLen, bool isFd);
uint8_t isotp_encode_first_frame(uint8_t* outData, uint8_t maxLen, uint32_t totalLength, const uint8_t* chunk, uint8_t chunkLen);
uint8_t isotp_encode_consecutive_frame(uint8_t* outData, uint8_t maxLen, uint8_t sn, const uint8_t* chunk, uint8_t chunkLen);

bool isotp_tx_start(IsoTpChannel* chan, const uint8_t* payload, uint32_t length)
{
   if(!chan || !payload || length == 0 || length > ISOTP_MAX_MSG_SIZE)
   {
      return false;
   }

   memcpy(chan->txBuffer, payload, length);
   chan->txTotalLen = length;
   chan->txSentLen = 0;
   chan->txSequenceNumber = 1;
   chan->txBlockSize = 0;
   chan->txSeparationTime = 0;

   uint32_t maxSf = chan->config.isFd ? 62 : 7;
   if(length <= maxSf)
   {
      // Single frame transmission
      chan->state = ISOTP_STATE_SENDING;
   }
   else
   {
      // Multi-frame segmentation starting with First Frame
      chan->state = ISOTP_STATE_SENDING;
   }

   uint64_t nowUs = ec_get_time_us();
   chan->lastActivityTime.seconds = nowUs / 1000000ULL;
   chan->lastActivityTime.microseconds = (uint32_t)(nowUs % 1000000ULL);
   return true;
}

// Polls the transmitter to generate the next CAN frame (SF, FF, or CF)
bool isotp_tx_poll(IsoTpChannel* chan, uint64_t currentMs, CanFrame* outFrame, bool* frameReady)
{
   if(!chan || !outFrame || !frameReady) return false;
   *frameReady = false;

   if(chan->state != ISOTP_STATE_SENDING) return true;

   uint32_t maxSf = chan->config.isFd ? 62 : 7;
   uint8_t framePayload[CAN_FD_MAX_DATA_LEN] = { 0 };

   if(chan->txTotalLen <= maxSf && chan->txSentLen == 0)
   {
      // Generate Single Frame
      can_frame_init(outFrame, chan->config.txId, chan->config.isExtended, chan->config.isFd);
      uint8_t encLen = isotp_encode_single_frame(framePayload, sizeof(framePayload),
                                                 chan->txBuffer, (uint8_t)chan->txTotalLen,
                                                 chan->config.isFd);
      can_frame_set_payload(outFrame, framePayload, encLen);
      chan->txSentLen = chan->txTotalLen;
      chan->state = ISOTP_STATE_IDLE; // Transmission complete!
      *frameReady = true;
      return true;
   }

   if(chan->txSentLen == 0)
   {
      // Generate First Frame
      can_frame_init(outFrame, chan->config.txId, chan->config.isExtended, chan->config.isFd);
      uint8_t chunkSize = chan->config.isFd ? 58 : 6;
      uint8_t encLen = isotp_encode_first_frame(framePayload, sizeof(framePayload),
                                                chan->txTotalLen, chan->txBuffer, chunkSize);
      can_frame_set_payload(outFrame, framePayload, encLen);
      chan->txSentLen = chunkSize;
      chan->state = ISOTP_STATE_WAIT_FC; // Wait for receiver Flow Control
      *frameReady = true;
      return true;
   }

   // Consecutive Frame (CF) generation
   if(chan->txSentLen < chan->txTotalLen)
   {
      uint8_t maxCfChunk = chan->config.isFd ? 63 : 7;
      uint32_t remaining = chan->txTotalLen - chan->txSentLen;
      uint8_t chunk = (remaining > maxCfChunk) ? maxCfChunk : (uint8_t)remaining;

      can_frame_init(outFrame, chan->config.txId, chan->config.isExtended, chan->config.isFd);
      uint8_t encLen = isotp_encode_consecutive_frame(framePayload, sizeof(framePayload),
                                                      chan->txSequenceNumber,
                                                      chan->txBuffer + chan->txSentLen, chunk);
      can_frame_set_payload(outFrame, framePayload, encLen);
      chan->txSentLen += chunk;
      chan->txSequenceNumber = (chan->txSequenceNumber + 1) & 0x0F;

      if(chan->txSentLen >= chan->txTotalLen)
      {
         chan->state = ISOTP_STATE_IDLE; // Done!
      }

      *frameReady = true;
      return true;
   }

   return true;
}
