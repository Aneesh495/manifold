// tests/regression/test_protocol_edge_cases.ec
// Comprehensive regression tests for boundary conditions, security lockouts, and buffer overflows.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "uds.eh"
#include "doip.eh"
#include "someip.eh"
#include "xcp.eh"
#include "secoc.eh"
#include "routing.eh"
#include "ec_runtime.h"

// Forward declarations
bool test_can_fd_stuff_bit_edge_cases(void);
bool test_isotp_zero_length_and_wrap(void);
bool test_uds_security_lockout_and_seed_expiration(void);
bool test_doip_socket_flood_and_nack(void);
bool test_xcp_boundary_violations(void);
bool test_secoc_freshness_rollover(void);
bool test_dtc_and_did_catalogs(void);

bool test_can_fd_stuff_bit_edge_cases(void)
{
   // 1. Data payload consisting of all 0xFF (maximum run of 1s)
   uint8_t allOnes[64];
   memset(allOnes, 0xFF, sizeof(allOnes));
   uint32_t crc1 = can_fd_crc21(allOnes, 64, 0x07);
   assert(crc1 != 0);

   // 2. Data payload consisting of all 0x00 (maximum run of 0s)
   uint8_t allZeros[64];
   memset(allZeros, 0x00, sizeof(allZeros));
   uint32_t crc2 = can_fd_crc21(allZeros, 64, 0x00);
   assert(crc2 != 0 && crc2 != crc1);

   // 3. Frame initialization with 29-bit extended ID edge cases
   CanFrame extFrame;
   can_frame_init(&extFrame, 0x1FFFFFFF, true, true);
   assert(extFrame.flags.isExtended == 1);
   assert(extFrame.arbitrationId == 0x1FFFFFFF);

   // Masking test: bits beyond 29-bit must be cleared
   can_frame_init(&extFrame, 0xFFFFFFFF, true, true);
   assert(extFrame.arbitrationId == 0x1FFFFFFF);

   return true;
}

bool test_isotp_zero_length_and_wrap(void)
{
   IsoTpConfig txCfg = { .rxId = 0x7E8, .txId = 0x7E0, .isExtended = false, .isFd = false, .blockSize = 8, .separationTime = 0 };
   IsoTpChannel txChan;
   isotp_channel_init(&txChan, &txCfg);

   // 1. Reject zero-length payload
   uint8_t dummy[1] = { 0 };
   assert(!isotp_tx_start(&txChan, dummy, 0));

   // 2. Reject NULL buffer
   assert(!isotp_tx_start(&txChan, NULL, 10));

   // 3. Multi-frame initiation and Flow Control OVERFLOW abort
   uint8_t payload[64];
   memset(payload, 0xEE, sizeof(payload));
   assert(isotp_tx_start(&txChan, payload, 64));

   CanFrame ff;
   bool ready = false;
   assert(isotp_tx_poll(&txChan, 0, &ff, &ready));
   assert(ready);
   assert(txChan.state == ISOTP_STATE_WAIT_FC);

   // Receive Flow Control OVERFLOW: must set error state
   assert(!isotp_fc_process(&txChan, ISOTP_FS_OVERFLOW, 0, 0));
   assert(txChan.state == ISOTP_STATE_ERROR);

   return true;
}

bool test_uds_security_lockout_and_seed_expiration(void)
{
   UdsServer server;
   uds_server_init(&server);

   uint8_t resp[256];
   uint32_t respLen = 0;

   // 1. Request seed for Level 1 (Service 0x27, Sub 0x01)
   uint8_t reqSeed[2] = { UDS_SID_SECURITY_ACCESS, 0x01 };
   uds_server_process_request(&server, reqSeed, 2, resp, &respLen);
   assert(respLen == 6);
   assert(resp[0] == 0x67 && resp[1] == 0x01);
   uint32_t seed = ((uint32_t)resp[2] << 24) | ((uint32_t)resp[3] << 16) | ((uint32_t)resp[4] << 8) | resp[5];
   assert(seed != 0);

   // 2. Send invalid key (Sub 0x02 with wrong key)
   uint8_t badKey[6] = { UDS_SID_SECURITY_ACCESS, 0x02, 0x00, 0x00, 0x00, 0x00 };
   uds_server_process_request(&server, badKey, 6, resp, &respLen);
   assert(respLen == 3);
   assert(resp[0] == 0x7F && resp[1] == 0x27 && resp[2] == NRC_INVALID_KEY);
   assert(server.security.failedAttempts == 1);

   // 3. Repeat bad keys to trigger lockout threshold (3 failed attempts)
   // Each attempt requires fresh seed
   uds_server_process_request(&server, reqSeed, 2, resp, &respLen);
   uds_server_process_request(&server, badKey, 6, resp, &respLen);
   assert(server.security.failedAttempts == 2);

   uds_server_process_request(&server, reqSeed, 2, resp, &respLen);
   uds_server_process_request(&server, badKey, 6, resp, &respLen);
   assert(server.security.failedAttempts == 3);
   assert(resp[0] == 0x7F && resp[2] == NRC_EXCEEDED_NUMBER_OF_ATTEMPTS);

   // 4. While locked out, any further request is rejected with NRC 0x37 (RequiredTimeDelayNotExpired)
   uds_server_process_request(&server, reqSeed, 2, resp, &respLen);
   assert(resp[0] == 0x7F && resp[2] == NRC_REQUIRED_TIME_DELAY_NOT_EXPIRED);

   return true;
}

bool test_doip_socket_flood_and_nack(void)
{
   DoipNode node;
   doip_node_init(&node, "TESTVIN1234567890", 0x0E80, NULL, NULL);

   uint8_t respBuf[64];

   // Register 8 sockets (DOIP_MAX_SESSIONS)
   for(uint32_t i = 0; i < DOIP_MAX_SESSIONS; i++)
   {
      uint16_t sa = 0x0E00 + (uint16_t)i;
      uint8_t actReq[7] = { (uint8_t)((sa >> 8) & 0xFF), (uint8_t)(sa & 0xFF), 0x00, 0, 0, 0, 0 };
      uint32_t len = doip_process_routing_activation(&node, 100 + i, actReq, sizeof(actReq), respBuf, sizeof(respBuf));
      assert(len == 17 && respBuf[12] == DOIP_ROUTING_SUCCESS);
   }
   assert(node.activeSessionCount == DOIP_MAX_SESSIONS);

   // 9th socket registration must fail with DOIP_ROUTING_ERR_ALL_SOCKETS_REGISTERED (0x01)
   uint8_t actReq9[7] = { 0x0E, 0x99, 0x00, 0, 0, 0, 0 };
   uint32_t len = doip_process_routing_activation(&node, 999, actReq9, sizeof(actReq9), respBuf, sizeof(respBuf));
   assert(len == 17);
   assert(respBuf[12] == DOIP_ROUTING_ERR_ALL_SOCKETS_REGISTERED);

   // Close socket 100
   assert(doip_close_session(&node, 100));
   assert(node.activeSessionCount == (DOIP_MAX_SESSIONS - 1));

   // Now 9th socket succeeds
   len = doip_process_routing_activation(&node, 999, actReq9, sizeof(actReq9), respBuf, sizeof(respBuf));
   assert(len == 17 && respBuf[12] == DOIP_ROUTING_SUCCESS);

   return true;
}

bool test_xcp_boundary_violations(void)
{
   XcpServer server;
   xcp_server_init(&server);

   uint8_t connectCmd[2] = { XCP_CMD_CONNECT, 0x00 };
   uint8_t resp[64];
   xcp_process_command(&server, connectCmd, 2, resp, sizeof(resp));

   // 1. SET_MTA pointing beyond page size (4096 bytes)
   uint8_t badMtaCmd[8] = { XCP_CMD_SET_MTA, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00 }; // 0x2000 = 8192
   xcp_process_command(&server, badMtaCmd, 8, resp, sizeof(resp));

   // Attempt upload: must return ACCESS_DENIED
   uint8_t upCmd[2] = { XCP_CMD_UPLOAD, 4 };
   uint32_t len = xcp_process_command(&server, upCmd, 2, resp, sizeof(resp));
   assert(len == 2 && resp[0] == XCP_PID_ERROR_RESPONSE && resp[1] == XCP_ERR_ACCESS_DENIED);

   // 2. Checksum block size extending past buffer limit
   uint8_t goodMta[8] = { XCP_CMD_SET_MTA, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00 }; // 0x0F00 = 3840
   xcp_process_command(&server, goodMta, 8, resp, sizeof(resp));

   // Checksum 1000 bytes: 3840 + 1000 = 4840 > 4096 -> must fail with OUT_OF_RANGE
   uint8_t chkCmd[8] = { XCP_CMD_BUILD_CHECKSUM, 0, 0, 0, 0xE8, 0x03, 0x00, 0x00 }; // 1000 bytes
   len = xcp_process_command(&server, chkCmd, 8, resp, sizeof(resp));
   assert(len == 2 && resp[0] == XCP_PID_ERROR_RESPONSE && resp[1] == XCP_ERR_OUT_OF_RANGE);

   return true;
}

bool test_secoc_freshness_rollover(void)
{
   SecOcConfig cfg;
   cfg.dataId = 0x2000;
   const uint8_t key[16] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
   memcpy(cfg.key, key, 16);
   cfg.macTruncationBits = 64;
   cfg.freshnessBits = 64;

   uint8_t data[8] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE };
   uint8_t mac1[8], mac2[8];

   // Freshness value rollover from 0xFFFFFFFFFFFFFFFF to 0
   assert(secoc_generate_mac(&cfg, data, 8, 0xFFFFFFFFFFFFFFFFULL, mac1));
   assert(secoc_generate_mac(&cfg, data, 8, 0x0000000000000000ULL, mac2));

   // Different freshness values must yield completely different MACs
   assert(memcmp(mac1, mac2, 8) != 0);

   // Verification with wrong freshness must fail
   assert(!secoc_verify_mac(&cfg, data, 8, 0x0000000000000001ULL, mac1));

   return true;
}

bool test_dtc_and_did_catalogs(void)
{
   // 1. DTC Catalog lookup
   const char* desc1 = dtc_catalog_lookup_description(0x010000);
   assert(strcmp(desc1, "Mass or Volume Air Flow Circuit Malfunction") == 0);

   const char* descU = dtc_catalog_lookup_description(0xC00000);
   assert(strcmp(descU, "High Speed CAN Communication Bus Malfunction") == 0);

   const char* descUnknown = dtc_catalog_lookup_description(0x999999);
   assert(strcmp(descUnknown, "Unknown Diagnostic Trouble Code") == 0);

   // 2. FaultManager population from catalog
   FaultManager mgr;
   fault_manager_init(&mgr);
   dtc_catalog_populate_manager(&mgr);
   assert(mgr.count > 40);
   DtcEntry* found = fault_manager_find_dtc(&mgr, 0x010000);
   assert(found != NULL);
   assert(found->code == 0x010000);

   // 3. UDS DID Catalog lookup
   const UdsDidDefinition* def = uds_did_catalog_lookup(0xF190);
   assert(def != NULL);
   assert(strcmp(def->name, "VehicleIdentificationNumber (VIN)") == 0);
   assert(def->length == 17);

   uint8_t payload[32];
   uint32_t payloadLen = 0;
   assert(uds_did_catalog_read(0xF190, payload, &payloadLen, sizeof(payload)));
   assert(payloadLen == 17);
   assert(memcmp(payload, "1HGBH41JXMN109186", 17) == 0);

   // Non-existent DID lookup
   assert(uds_did_catalog_lookup(0x1234) == NULL);

   return true;
}
