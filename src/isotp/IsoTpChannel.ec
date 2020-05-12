// src/isotp/IsoTpChannel.ec
// Multi-channel ISO-TP session manager and CAN FD large single frame dispatcher.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "ec_runtime.h"

#define MAX_ISOTP_CHANNELS 8

// Forward declarations from IsoTpTx.ec and IsoTpRx.ec
bool isotp_tx_start(IsoTpChannel* chan, const uint8_t* payload, uint32_t length);
bool isotp_tx_poll(IsoTpChannel* chan, uint64_t currentMs, CanFrame* outFrame, bool* frameReady);
bool isotp_rx_frame(IsoTpChannel* chan, const CanFrame* frame, uint8_t* outMsg, uint32_t* outLen, CanFrame* outFcFrame, bool* fcNeeded);

typedef struct IsoTpRouter
{
   IsoTpChannel channels[MAX_ISOTP_CHANNELS];
   uint32_t channelCount;
} IsoTpRouter;

void isotp_channel_init(IsoTpChannel* chan, const IsoTpConfig* config)
{
   if(!chan || !config) return;
   memset(chan, 0, sizeof(IsoTpChannel));
   chan->config = *config;
   chan->state = ISOTP_STATE_IDLE;
}

void isotp_router_init(IsoTpRouter* router)
{
   if(!router) return;
   memset(router, 0, sizeof(IsoTpRouter));
}

IsoTpChannel* isotp_router_add_channel(IsoTpRouter* router, const IsoTpConfig* config)
{
   if(!router || !config || router->channelCount >= MAX_ISOTP_CHANNELS) return NULL;

   IsoTpChannel* chan = &router->channels[router->channelCount++];
   isotp_channel_init(chan, config);
   return chan;
}

// Ingests an incoming CAN frame across all registered ISO-TP channels
bool isotp_router_process_frame(IsoTpRouter* router, const CanFrame* frame, uint8_t* outMsg, uint32_t* outLen, CanFrame* outFcFrame, bool* fcNeeded)
{
   if(!router || !frame || !outMsg || !outLen || !outFcFrame || !fcNeeded) return false;

   for(uint32_t i = 0; i < router->channelCount; i++)
   {
      IsoTpChannel* chan = &router->channels[i];
      if(chan->config.rxId == frame->arbitrationId)
      {
         return isotp_rx_frame(chan, frame, outMsg, outLen, outFcFrame, fcNeeded);
      }
   }
   return false;
}
