// tests/unit/test_dtc.ec
// Unit tests for ISO 14229-1 Diagnostic Trouble Code qualification, debouncing,
// snapshot freeze-frame serialization, aging, and non-volatile flash storage.

#include <stdio.h>
#include <assert.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "dtc.eh"
#include "core.eh"
#include "ec_runtime.h"

// Forward declarations of DTC and UDS components
void freeze_frame_set_telemetry(double speed, double rpm, double battery, double coolant);
uint32_t freeze_frame_serialize(const FreezeFrame* ff, uint8_t* outBuf, uint32_t maxLen);

bool fault_storage_commit(const FaultManager* mgr);
bool fault_storage_restore(FaultManager* mgr);

FaultManager* uds_get_fault_manager(void);
void uds_server_init(UdsServer* server);
void uds_server_process_request(UdsServer* server, const uint8_t* req, uint32_t reqLen, uint8_t* resp, uint32_t* respLen);

bool test_dtc_debouncing_and_qualification(void)
{
   FaultManager mgr;
   fault_manager_init(&mgr);

   // Add DTC P0100 (Mass Air Flow circuit malfunction): code 0x010000
   DtcEntry* entry = fault_manager_add_dtc(&mgr, 0x010000, 30, -20);
   assert(entry != NULL);
   assert(entry->debounceCounter == 0);
   // Initial status: not completed since clear | not completed this cycle
   assert(entry->statusByte == 0x50);

   // Report failed: debounce increments +10 per fail step
   freeze_frame_set_telemetry(65.0, 2200.0, 14.1, 91.0);
   fault_manager_report_test_result(&mgr, 0x010000, true);
   assert(entry->debounceCounter == 10);
   assert(!(entry->statusByte & 0x08)); // Not confirmed yet

   fault_manager_report_test_result(&mgr, 0x010000, true);
   assert(entry->debounceCounter == 20);

   // 3rd failure reaches threshold 30: fault qualifies!
   fault_manager_report_test_result(&mgr, 0x010000, true);
   assert(entry->debounceCounter >= 30);
   assert(entry->statusByte & 0x01); // testFailed = 1
   assert(entry->statusByte & 0x04); // pendingDTC = 1
   assert(entry->statusByte & 0x08); // confirmedDTC = 1
   assert(entry->statusByte & 0x80); // warningIndicatorRequested = 1
   assert(entry->occurrenceCount == 1);

   // Verify snapshot freeze frame captured vehicle metrics
   assert(entry->freezeFrame.vehicleSpeedKph == 65.0);
   assert(entry->freezeFrame.engineRpm == 2200.0);
   assert(entry->freezeFrame.coolantTempC == 91.0);

   // Test pass healing
   fault_manager_report_test_result(&mgr, 0x010000, false);
   fault_manager_report_test_result(&mgr, 0x010000, false);
   fault_manager_report_test_result(&mgr, 0x010000, false);
   assert(entry->debounceCounter < 30);

   return true;
}

bool test_dtc_uds_service_19_and_14(void)
{
   UdsServer server;
   uds_server_init(&server);

   FaultManager* mgr = uds_get_fault_manager();
   fault_manager_init(mgr);

   // Add DTC P0300 (Random Misfire): 0x030000
   fault_manager_add_dtc(mgr, 0x030000, 20, -10);
   freeze_frame_set_telemetry(90.0, 3100.0, 13.8, 95.0);
   fault_manager_report_test_result(mgr, 0x030000, true);
   fault_manager_report_test_result(mgr, 0x030000, true); // Qualifies

   // Test Service 0x19 subfunction 0x01: reportNumberOfDTCByStatusMask
   uint8_t req19_01[3] = { 0x19, 0x01, 0x08 }; // confirmedDTC mask
   uint8_t resp[256];
   uint32_t respLen = 0;
   uds_server_process_request(&server, req19_01, 3, resp, &respLen);
   assert(respLen == 6);
   assert(resp[0] == 0x59);
   assert(resp[1] == 0x01);
   assert(resp[4] == 0x00 && resp[5] == 0x01); // 1 matching DTC

   // Test Service 0x19 subfunction 0x02: reportDTCByStatusMask
   uint8_t req19_02[3] = { 0x19, 0x02, 0x08 };
   uds_server_process_request(&server, req19_02, 3, resp, &respLen);
   assert(respLen == 7); // 3 header bytes + 4 bytes for 1 DTC
   assert(resp[0] == 0x59);
   assert(resp[1] == 0x02);
   assert(resp[3] == 0x03 && resp[4] == 0x00 && resp[5] == 0x00); // DTC 0x030000

   // Test Service 0x19 subfunction 0x04: reportDTCSnapshotRecordByDTCNumber
   uint8_t req19_04[6] = { 0x19, 0x04, 0x03, 0x00, 0x00, 0x01 };
   uds_server_process_request(&server, req19_04, 6, resp, &respLen);
   assert(respLen >= 7);
   assert(resp[0] == 0x59);
   assert(resp[1] == 0x04);
   assert(resp[2] == 0x03 && resp[3] == 0x00 && resp[4] == 0x00);

   // Test Service 0x14: ClearDiagnosticInformation (All DTCs: 0xFFFFFF)
   uint8_t req14[4] = { 0x14, 0xFF, 0xFF, 0xFF };
   uds_server_process_request(&server, req14, 4, resp, &respLen);
   assert(respLen == 1);
   assert(resp[0] == 0x54);

   // Re-query: count should now be 0 for confirmed DTCs
   uds_server_process_request(&server, req19_01, 3, resp, &respLen);
   assert(respLen == 6);
   assert(resp[4] == 0x00 && resp[5] == 0x00);

   return true;
}

bool test_dtc_flash_storage_persistence(void)
{
   FaultManager mgr1;
   fault_manager_init(&mgr1);

   fault_manager_add_dtc(&mgr1, 0x012345, 10, -5);
   fault_manager_report_test_result(&mgr1, 0x012345, true);

   // Commit to simulated flash NVRAM
   assert(fault_storage_commit(&mgr1));

   // Restore into separate manager instance
   FaultManager mgr2;
   fault_manager_init(&mgr2);
   assert(fault_storage_restore(&mgr2));

   assert(mgr2.count == 1);
   assert(mgr2.entries[0].code == 0x012345);
   assert(mgr2.entries[0].statusByte == mgr1.entries[0].statusByte);

   return true;
}
