// tests/unit/test_doip.ec
// Unit tests for ISO 13400-2 DoIP Header, Discovery, Activation, Alive Check, and Routing.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#include "types.eh"
#include "doip.eh"
#include "uds.eh"
#include "ec_runtime.h"

// Forward declarations of test functions
bool test_doip_header_codec_and_nack(void);
bool test_doip_vehicle_discovery(void);
bool test_doip_routing_activation_and_alive_check(void);
bool test_doip_diagnostic_message_routing(void);

bool test_doip_header_codec_and_nack(void)
{
   DoipHeader hdr;
   hdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   hdr.inverseVersion  = DOIP_INVERSE_VERSION;
   hdr.payloadType     = DOIP_TYPE_ROUTING_ACTIVATION_REQUEST;
   hdr.payloadLength   = 7;

   uint8_t buffer[64];
   assert(doip_header_encode(&hdr, buffer, sizeof(buffer)));

   // Verify big-endian wire format
   assert(buffer[0] == 0x02);
   assert(buffer[1] == 0xFD);
   assert(buffer[2] == 0x00 && buffer[3] == 0x05); // 0x0005
   assert(buffer[4] == 0x00 && buffer[5] == 0x00 && buffer[6] == 0x00 && buffer[7] == 0x07);

   // Decode valid header
   DoipHeader decoded;
   uint8_t nack = 0;
   assert(doip_header_decode(buffer, sizeof(buffer), &decoded, &nack));
   assert(decoded.protocolVersion == DOIP_PROTOCOL_VERSION);
   assert(decoded.payloadType == DOIP_TYPE_ROUTING_ACTIVATION_REQUEST);
   assert(decoded.payloadLength == 7);

   // Test pattern corruption (inverse version wrong)
   buffer[1] = 0xFE;
   assert(!doip_header_decode(buffer, sizeof(buffer), &decoded, &nack));
   assert(nack == DOIP_NACK_INCORRECT_PATTERN_FORMAT);
   buffer[1] = 0xFD; // Restore

   // Test unknown payload type
   buffer[2] = 0x12;
   buffer[3] = 0x34;
   assert(!doip_header_decode(buffer, sizeof(buffer), &decoded, &nack));
   assert(nack == DOIP_NACK_UNKNOWN_PAYLOAD_TYPE);

   // Test generic NACK construction
   uint8_t nackBuf[32];
   uint32_t nackLen = doip_build_generic_nack(DOIP_NACK_UNKNOWN_PAYLOAD_TYPE, nackBuf, sizeof(nackBuf));
   assert(nackLen == 9);
   assert(nackBuf[0] == 0x02 && nackBuf[1] == 0xFD);
   assert(nackBuf[2] == 0x00 && nackBuf[3] == 0x00); // DOIP_TYPE_GENERIC_NACK
   assert(nackBuf[7] == 0x01); // Length 1
   assert(nackBuf[8] == DOIP_NACK_UNKNOWN_PAYLOAD_TYPE);

   return true;
}

bool test_doip_vehicle_discovery(void)
{
   DoipNode node;
   const char* testVin = "WAUZZZ8V1GA000001";
   const uint8_t testEid[6] = { 0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E };
   const uint8_t testGid[6] = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };

   doip_node_init(&node, testVin, 0x0E80, testEid, testGid);

   // 1. Build Vehicle Announcement frame
   uint8_t annBuf[64];
   uint32_t annLen = doip_build_vehicle_announcement(&node, annBuf, sizeof(annBuf));
   assert(annLen == 41); // 8 header + 33 payload
   assert(annBuf[0] == 0x02 && annBuf[1] == 0xFD);
   assert(annBuf[2] == 0x00 && annBuf[3] == 0x04); // Type 0x0004
   assert(memcmp(annBuf + 8, testVin, 17) == 0);
   assert(annBuf[25] == 0x0E && annBuf[26] == 0x80); // Logical address 0x0E80
   assert(memcmp(annBuf + 27, testEid, 6) == 0);
   assert(memcmp(annBuf + 33, testGid, 6) == 0);

   // 2. Handle broadcast discovery request (0x0001)
   DoipHeader reqHdr;
   reqHdr.protocolVersion = DOIP_PROTOCOL_VERSION;
   reqHdr.inverseVersion  = DOIP_INVERSE_VERSION;
   reqHdr.payloadType     = DOIP_TYPE_VEHICLE_IDENT_REQUEST;
   reqHdr.payloadLength   = 0;
   uint8_t reqBuf[32];
   doip_header_encode(&reqHdr, reqBuf, sizeof(reqBuf));

   uint8_t respBuf[64];
   uint32_t respLen = doip_handle_vehicle_ident_request(&node, reqBuf, 8, respBuf, sizeof(respBuf));
   assert(respLen == 41);
   assert(respBuf[2] == 0x00 && respBuf[3] == 0x04);

   // 3. Handle EID-filtered request (0x0002) with match
   reqHdr.payloadType   = DOIP_TYPE_VEHICLE_IDENT_REQUEST_EID;
   reqHdr.payloadLength = 6;
   doip_header_encode(&reqHdr, reqBuf, sizeof(reqBuf));
   memcpy(reqBuf + 8, testEid, 6);
   respLen = doip_handle_vehicle_ident_request(&node, reqBuf, 14, respBuf, sizeof(respBuf));
   assert(respLen == 41);

   // 4. Handle EID-filtered request with mismatch
   reqBuf[8] = 0xFF; // Corrupt EID
   respLen = doip_handle_vehicle_ident_request(&node, reqBuf, 14, respBuf, sizeof(respBuf));
   assert(respLen == 0); // Must ignore mismatched filter

   return true;
}

static uint32_t g_timedOutConnId = 0;
static void test_timeout_callback(uint32_t connId)
{
   g_timedOutConnId = connId;
}

bool test_doip_routing_activation_and_alive_check(void)
{
   DoipNode node;
   doip_node_init(&node, "TESTVIN1234567890", 0x0E80, NULL, NULL);

   // 1. Valid routing activation request from client SA 0x0E00 on connId 100
   uint8_t actReq[7] = { 0x0E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
   uint8_t respBuf[64];
   uint32_t respLen = doip_process_routing_activation(&node, 100, actReq, sizeof(actReq), respBuf, sizeof(respBuf));
   assert(respLen == 17); // 8 header + 9 payload
   assert(respBuf[2] == 0x00 && respBuf[3] == 0x06); // Type 0x0006
   assert(respBuf[8] == 0x0E && respBuf[9] == 0x00); // Echo SA 0x0E00
   assert(respBuf[10] == 0x0E && respBuf[11] == 0x80); // Entity LA 0x0E80
   assert(respBuf[12] == DOIP_ROUTING_SUCCESS); // Code 0x10

   DoipSession* s = doip_find_session(&node, 100);
   assert(s != NULL && s->isActivated);
   assert(s->clientLogicalAddress == 0x0E00);

   // 2. Reject request with different SA on the same connection
   uint8_t actReqDiffSa[7] = { 0x0E, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00 };
   respLen = doip_process_routing_activation(&node, 100, actReqDiffSa, sizeof(actReqDiffSa), respBuf, sizeof(respBuf));
   assert(respLen == 17);
   assert(respBuf[12] == DOIP_ROUTING_ERR_SA_DIFFERENT);

   // 3. Reject duplicate SA registered on a second connection
   respLen = doip_process_routing_activation(&node, 101, actReq, sizeof(actReq), respBuf, sizeof(respBuf));
   assert(respLen == 17);
   assert(respBuf[12] == DOIP_ROUTING_ERR_SA_ALREADY_REGISTERED);

   // 4. Alive check request creation
   uint8_t aliveReqBuf[16];
   uint32_t aliveReqLen = doip_build_alive_check_request(aliveReqBuf, sizeof(aliveReqBuf));
   assert(aliveReqLen == 8);
   assert(aliveReqBuf[2] == 0x00 && aliveReqBuf[3] == 0x07);

   // 5. Alive check response handling
   s->aliveCheckPending = true;
   s->lastActivityMs = 1000;
   uint8_t aliveRespGood[2] = { 0x0E, 0x00 };
   assert(doip_process_alive_check_response(&node, 100, aliveRespGood, 2));
   assert(!s->aliveCheckPending);

   // 6. Alive check timeout supervision
   s->aliveCheckPending = true;
   s->lastActivityMs = 1000;
   g_timedOutConnId = 0;
   // Current time 1600ms exceeds 500ms timeout
   doip_check_alive_timeouts(&node, 1600, test_timeout_callback);
   assert(g_timedOutConnId == 100);
   assert(doip_find_session(&node, 100) == NULL); // Session should be closed

   return true;
}

static void mock_uds_handler(uint16_t sa, uint16_t ta, const uint8_t* udsReq, uint32_t udsLen, uint8_t* udsResp, uint32_t* udsRespLen, uint32_t maxRespLen)
{
   (void)sa;
   (void)ta;
   if(!udsReq || udsLen < 1 || !udsResp || maxRespLen < 8) return;

   // Check if ReadDataByIdentifier (0x22) for DID 0xF190
   if(udsReq[0] == 0x22 && udsLen >= 3 && udsReq[1] == 0xF1 && udsReq[2] == 0x90)
   {
      udsResp[0] = 0x62; // Positive response
      udsResp[1] = 0xF1;
      udsResp[2] = 0x90;
      memcpy(udsResp + 3, "MANIFOLD_GATEWAY", 16);
      *udsRespLen = 19;
   }
}

bool test_doip_diagnostic_message_routing(void)
{
   DoipNode node;
   doip_node_init(&node, "TESTVIN1234567890", 0x0E80, NULL, NULL);

   // Activate session for tester SA 0x0E00 on connId 200
   uint8_t actReq[7] = { 0x0E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
   uint8_t actResp[64];
   doip_process_routing_activation(&node, 200, actReq, sizeof(actReq), actResp, sizeof(actResp));

   // 1. Valid diagnostic request: SA=0x0E00, TA=0x0E80, UDS=0x22 0xF1 0x90
   uint8_t diagPayload[7] = { 0x0E, 0x00, 0x0E, 0x80, 0x22, 0xF1, 0x90 };
   uint8_t outBuf[256];
   uint32_t outLen = doip_process_diagnostic_message(&node, 200, diagPayload, sizeof(diagPayload), outBuf, sizeof(outBuf), mock_uds_handler);

   assert(outLen == 8 + 4 + 19); // 8 header + 4 SA/TA + 19 UDS response = 31 bytes
   assert(outBuf[2] == 0x80 && outBuf[3] == 0x01); // Type 0x8001
   // SA is responder 0x0E80, TA is tester 0x0E00
   assert(outBuf[8] == 0x0E && outBuf[9] == 0x80);
   assert(outBuf[10] == 0x0E && outBuf[11] == 0x00);
   assert(outBuf[12] == 0x62 && outBuf[13] == 0xF1 && outBuf[14] == 0x90);

   // 2. Reject mismatched SA with Diagnostic NACK (0x8003)
   uint8_t diagBadSa[7] = { 0x0E, 0x05, 0x0E, 0x80, 0x22, 0xF1, 0x90 };
   outLen = doip_process_diagnostic_message(&node, 200, diagBadSa, sizeof(diagBadSa), outBuf, sizeof(outBuf), mock_uds_handler);
   assert(outLen == 8 + 4 + 1); // 13 bytes
   assert(outBuf[2] == 0x80 && outBuf[3] == 0x03); // Type 0x8003
   assert(outBuf[12] == DOIP_DIAG_NACK_INVALID_SOURCE_ADDRESS);

   // 3. Reject unknown TA with Diagnostic NACK (0x8003)
   uint8_t diagBadTa[7] = { 0x0E, 0x00, 0x99, 0x99, 0x22, 0xF1, 0x90 };
   outLen = doip_process_diagnostic_message(&node, 200, diagBadTa, sizeof(diagBadTa), outBuf, sizeof(outBuf), mock_uds_handler);
   assert(outLen == 8 + 4 + 1);
   assert(outBuf[2] == 0x80 && outBuf[3] == 0x03);
   assert(outBuf[12] == DOIP_DIAG_NACK_UNKNOWN_TARGET_ADDRESS);

   return true;
}
