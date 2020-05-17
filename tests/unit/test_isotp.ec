// tests/unit/test_isotp.ec
// Comprehensive ISO 15765-2 transport layer tests: Single Frame, First Frame,
// Flow Control CTS handshake, Consecutive Frame sequence rollover, and reassembly.

#include <stdio.h>
#include <assert.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "core.eh"
#include "ec_runtime.h"

// Forward declarations of ISO-TP components
bool isotp_tx_start(IsoTpChannel* chan, const uint8_t* payload, uint32_t length);
bool isotp_tx_poll(IsoTpChannel* chan, uint64_t currentMs, CanFrame* outFrame, bool* frameReady);
bool isotp_rx_frame(IsoTpChannel* chan, const CanFrame* frame, uint8_t* outMsg, uint32_t* outLen, CanFrame* outFcFrame, bool* fcNeeded);
bool isotp_fc_process(IsoTpChannel* chan, IsoTpFlowStatus fs, uint8_t bs, uint8_t stMin);

bool test_isotp_single_frame(void)
{
   IsoTpConfig txCfg = { .rxId = 0x7E8, .txId = 0x7E0, .isExtended = false, .isFd = false, .blockSize = 0, .separationTime = 0 };
   IsoTpConfig rxCfg = { .rxId = 0x7E0, .txId = 0x7E8, .isExtended = false, .isFd = false, .blockSize = 0, .separationTime = 0 };

   IsoTpChannel txChan, rxChan;
   isotp_channel_init(&txChan, &txCfg);
   isotp_channel_init(&rxChan, &rxCfg);

   // 5-byte payload (fits in single frame)
   uint8_t req[5] = { 0x22, 0xF1, 0x90, 0x01, 0x02 };
   assert(isotp_tx_start(&txChan, req, 5));

   CanFrame frame;
   bool ready = false;
   assert(isotp_tx_poll(&txChan, 0, &frame, &ready));
   assert(ready);
   assert(frame.arbitrationId == 0x7E0);
   assert(frame.payloadLength == 6); // 1 byte N_PCI + 5 data bytes
   assert((frame.data[0] >> 4) == ISOTP_FRAME_SINGLE);
   assert((frame.data[0] & 0x0F) == 5);

   uint8_t outMsg[128] = { 0 };
   uint32_t outLen = 0;
   CanFrame fcFrame;
   bool fcNeeded = false;
   assert(isotp_rx_frame(&rxChan, &frame, outMsg, &outLen, &fcFrame, &fcNeeded));
   assert(!fcNeeded);
   assert(outLen == 5);
   assert(memcmp(outMsg, req, 5) == 0);

   return true;
}

bool test_isotp_can_fd_large_single_frame(void)
{
   IsoTpConfig txCfg = { .rxId = 0x7E8, .txId = 0x7E0, .isExtended = false, .isFd = true };
   IsoTpConfig rxCfg = { .rxId = 0x7E0, .txId = 0x7E8, .isExtended = false, .isFd = true };

   IsoTpChannel txChan, rxChan;
   isotp_channel_init(&txChan, &txCfg);
   isotp_channel_init(&rxChan, &rxCfg);

   // 48-byte payload (fits in CAN FD large single frame, SF_DL = 48)
   uint8_t fdData[48];
   for(int i = 0; i < 48; i++) fdData[i] = (uint8_t)(i ^ 0xA5);

   assert(isotp_tx_start(&txChan, fdData, 48));

   CanFrame frame;
   bool ready = false;
   assert(isotp_tx_poll(&txChan, 0, &frame, &ready));
   assert(ready);
   assert(frame.flags.isFd);
   assert(frame.data[0] == 0x00); // CAN FD large SF escape byte
   assert(frame.data[1] == 48);

   uint8_t outMsg[128] = { 0 };
   uint32_t outLen = 0;
   CanFrame fcFrame;
   bool fcNeeded = false;
   assert(isotp_rx_frame(&rxChan, &frame, outMsg, &outLen, &fcFrame, &fcNeeded));
   assert(!fcNeeded);
   assert(outLen == 48);
   assert(memcmp(outMsg, fdData, 48) == 0);

   return true;
}

bool test_isotp_multi_frame_handshake_and_rollover(void)
{
   IsoTpConfig txCfg = { .rxId = 0x7E8, .txId = 0x7E0, .isExtended = false, .isFd = false, .blockSize = 0, .separationTime = 0 };
   IsoTpConfig rxCfg = { .rxId = 0x7E0, .txId = 0x7E8, .isExtended = false, .isFd = false, .blockSize = 0, .separationTime = 0 };

   IsoTpChannel txChan, rxChan;
   isotp_channel_init(&txChan, &txCfg);
   isotp_channel_init(&rxChan, &rxCfg);

   // 250-byte payload (requires FF + ~35 CFs, forcing sequence number rollover past 15 multiple times)
   uint8_t largeData[250];
   for(int i = 0; i < 250; i++) largeData[i] = (uint8_t)(i & 0xFF);

   assert(isotp_tx_start(&txChan, largeData, 250));

   // Step 1: First Frame
   CanFrame ffFrame;
   bool ready = false;
   assert(isotp_tx_poll(&txChan, 0, &ffFrame, &ready));
   assert(ready);
   assert(txChan.state == ISOTP_STATE_WAIT_FC);
   assert((ffFrame.data[0] >> 4) == ISOTP_FRAME_FIRST);

   // Ingest FF at receiver: must produce Flow Control CTS
   uint8_t outMsg[512] = { 0 };
   uint32_t outLen = 0;
   CanFrame fcFrame;
   bool fcNeeded = false;
   assert(!isotp_rx_frame(&rxChan, &ffFrame, outMsg, &outLen, &fcFrame, &fcNeeded));
   assert(fcNeeded);
   assert(rxChan.state == ISOTP_STATE_RECEIVING);
   assert((fcFrame.data[0] >> 4) == ISOTP_FRAME_FLOW_CONTROL);

   // Step 2: Feed Flow Control CTS back to transmitter
   assert(isotp_fc_process(&txChan, ISOTP_FS_CTS, fcFrame.data[1], fcFrame.data[2]));
   assert(txChan.state == ISOTP_STATE_SENDING);

   // Step 3: Emit and deliver all Consecutive Frames (CF)
   bool completed = false;
   while(txChan.state == ISOTP_STATE_SENDING)
   {
      CanFrame cfFrame;
      ready = false;
      if(isotp_tx_poll(&txChan, 0, &cfFrame, &ready) && ready)
      {
         fcNeeded = false;
         if(isotp_rx_frame(&rxChan, &cfFrame, outMsg, &outLen, &fcFrame, &fcNeeded))
         {
            completed = true;
            break;
         }
      }
   }

   assert(completed);
   assert(outLen == 250);
   assert(memcmp(outMsg, largeData, 250) == 0);
   assert(rxChan.state == ISOTP_STATE_IDLE);

   return true;
}
