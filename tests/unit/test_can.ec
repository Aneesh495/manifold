// tests/unit/test_can.ec
// Unit tests for CAN 2.0B, CAN FD, CRC-15/17/21, mailbox filters, and LIN 2.2 transceiver.

#include <stdio.h>
#include <assert.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "core.eh"
#include "ec_runtime.h"

bool test_can_frame_and_dlc(void)
{
   CanFrame frame;
   can_frame_init(&frame, 0x123, false, false);
   assert(frame.arbitrationId == 0x123);
   assert(!frame.flags.isExtended);
   assert(!frame.flags.isFd);

   uint8_t payload[8] = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
   assert(can_frame_set_payload(&frame, payload, 8));
   assert(frame.dlc == 8);
   assert(frame.payloadLength == 8);

   // CAN FD large frame with padding
   CanFrame fdFrame;
   can_frame_init(&fdFrame, 0x18DAF110, true, true);
   assert(fdFrame.arbitrationId == 0x18DAF110);
   assert(fdFrame.flags.isExtended);
   assert(fdFrame.flags.isFd);

   // Set 10 bytes: CAN FD should pad to 12 bytes with 0xCC
   uint8_t fdPayload[10] = { 0 };
   memset(fdPayload, 0x55, 10);
   assert(can_frame_set_payload(&fdFrame, fdPayload, 10));
   assert(fdFrame.dlc == 9);
   assert(fdFrame.payloadLength == 12);
   assert(fdFrame.data[9] == 0x55);
   assert(fdFrame.data[10] == 0xCC);
   assert(fdFrame.data[11] == 0xCC);

   char candumpStr[128];
   int len = can_frame_to_candump(&fdFrame, "can1", candumpStr, sizeof(candumpStr));
   assert(len > 0);
   assert(strstr(candumpStr, "can1") != NULL);
   assert(strstr(candumpStr, "18DAF110") != NULL);

   return true;
}

bool test_can_crc_algorithms(void)
{
   uint8_t testData[8] = { 0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
   uint16_t crc15 = can_crc15(testData, 8);
   assert(crc15 != 0);

   CanFrame frame;
   can_frame_init(&frame, 0x7DF, false, false);
   can_frame_set_payload(&frame, testData, 8);
   uint32_t computed = can_frame_compute_crc(&frame, 0);
   assert(computed == crc15);
   assert(can_frame_verify_crc(&frame, 0, crc15));

   CanFrame fd17;
   can_frame_init(&fd17, 0x7DF, false, true);
   uint8_t d16[16];
   memset(d16, 0xAA, 16);
   can_frame_set_payload(&fd17, d16, 16);
   uint32_t crc17 = can_frame_compute_crc(&fd17, 3);
   assert(crc17 != 0);
   assert(can_frame_verify_crc(&fd17, 3, crc17));

   CanFrame fd21;
   can_frame_init(&fd21, 0x7DF, false, true);
   uint8_t d64[64];
   memset(d64, 0xBB, 64);
   can_frame_set_payload(&fd21, d64, 64);
   uint32_t crc21 = can_frame_compute_crc(&fd21, 5);
   assert(crc21 != 0);
   assert(can_frame_verify_crc(&fd21, 5, crc21));

   return true;
}

bool test_can_controller_filters_and_errors(void)
{
   CanController ctrl;
   can_controller_init(&ctrl, 0);

   assert(can_controller_add_filter(&ctrl, 0x7E0, 0x7F8, false));

   CanFrame matching;
   can_frame_init(&matching, 0x7E0, false, false);
   assert(can_controller_matches_filter(&ctrl, &matching));

   CanFrame nonMatching;
   can_frame_init(&nonMatching, 0x123, false, false);
   assert(!can_controller_matches_filter(&ctrl, &nonMatching));

   for(int i = 0; i < 35; i++)
   {
      can_controller_record_tx_error(&ctrl);
   }
   assert(ctrl.state == CAN_STATE_BUS_OFF);

   for(int i = 0; i < 127; i++)
   {
      assert(!can_controller_recover_bus_off(&ctrl));
   }
   assert(can_controller_recover_bus_off(&ctrl));
   assert(ctrl.state == CAN_STATE_ERROR_ACTIVE);

   return true;
}

bool test_can_transceiver_and_arbitration(void)
{
   CanTransceiver* xcvr = can_transceiver_create(1, "vcan0", true);

   CanFrame frame1, frame2, frame3;
   can_frame_init(&frame1, 0x300, false, false);
   can_frame_init(&frame2, 0x100, false, false);
   can_frame_init(&frame3, 0x200, false, false);

   CanFrame* pending[3] = { &frame1, &frame2, &frame3 };
   uint32_t winningIdx = 0;
   CanFrame* winner = can_transceiver_arbitrate(pending, 3, &winningIdx);
   assert(winner == &frame2);
   assert(winningIdx == 1);
   assert(winner->arbitrationId == 0x100);

   assert(can_transceiver_transmit(xcvr, &frame2));
   CanFrame rxFrame;
   assert(can_transceiver_receive(xcvr, &rxFrame));
   assert(rxFrame.arbitrationId == 0x100);

   can_transceiver_destroy(xcvr);
   return true;
}

bool test_lin_pid_and_checksum(void)
{
   for(uint8_t id = 0; id < 64; id++)
   {
      uint8_t pid = lin_compute_pid(id);
      assert(lin_verify_pid(pid));
      assert((pid & 0x3F) == id);
   }

   assert(lin_compute_pid(0x01) == 0xC1);
   assert(lin_compute_pid(0x3C) == 0x3C);

   uint8_t data[4] = { 0x01, 0xFF, 0x02, 0x03 };
   uint8_t pid = lin_compute_pid(0x10);
   uint8_t csum = lin_compute_checksum(pid, data, 4, true);
   assert(csum != 0);

   return true;
}
