// tests/unit/test_someip.ec
// Unit tests for AUTOSAR SOME/IP message framing, type-safe serialization, SD, and RPC.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <math.h>

#include "types.eh"
#include "someip.eh"
#include "ec_runtime.h"

// Forward declarations
bool test_someip_header_and_payload_serialization(void);
bool test_someip_service_discovery_offers_and_queries(void);
bool test_someip_rpc_dispatching_and_notifications(void);

bool test_someip_header_and_payload_serialization(void)
{
   // 1. Header encode and decode
   SomeIpHeader hdr;
   hdr.serviceId        = 0x1234;
   hdr.methodId         = 0x0001;
   hdr.length           = 16; // 8 bytes header remainder + 8 bytes payload
   hdr.clientId         = 0xCAFE;
   hdr.sessionId        = 0x0042;
   hdr.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   hdr.interfaceVersion = 0x01;
   hdr.messageType      = SOMEIP_MSG_REQUEST;
   hdr.returnCode       = SOMEIP_RET_E_OK;

   uint8_t hdrBuf[32];
   assert(someip_header_encode(&hdr, hdrBuf, sizeof(hdrBuf)));

   assert(hdrBuf[0] == 0x12 && hdrBuf[1] == 0x34);
   assert(hdrBuf[2] == 0x00 && hdrBuf[3] == 0x01);
   assert(hdrBuf[4] == 0x00 && hdrBuf[5] == 0x00 && hdrBuf[6] == 0x00 && hdrBuf[7] == 0x10);
   assert(hdrBuf[8] == 0xCA && hdrBuf[9] == 0xFE);
   assert(hdrBuf[10] == 0x00 && hdrBuf[11] == 0x42);
   assert(hdrBuf[12] == 0x01);
   assert(hdrBuf[13] == 0x01);
   assert(hdrBuf[14] == 0x00);
   assert(hdrBuf[15] == 0x00);

   SomeIpHeader decHdr;
   assert(someip_header_decode(hdrBuf, 16, &decHdr));
   assert(decHdr.serviceId == 0x1234);
   assert(decHdr.methodId == 0x0001);
   assert(decHdr.clientId == 0xCAFE);
   assert(decHdr.sessionId == 0x0042);
   assert(decHdr.length == 16);

   // 2. Serializer and Deserializer primitives test
   uint8_t payloadBuf[256];
   SomeIpSerializer ser;
   someip_serializer_init(&ser, payloadBuf, sizeof(payloadBuf));

   assert(someip_serialize_uint8(&ser, 0xA5));
   assert(someip_serialize_uint16(&ser, 0x1234));
   assert(someip_serialize_uint32(&ser, 0xDEADBEEF));
   assert(someip_serialize_uint64(&ser, 0x0123456789ABCDEFULL));
   assert(someip_serialize_float32(&ser, 123.456f));
   assert(someip_serialize_float64(&ser, 98765.4321));
   assert(someip_serialize_string(&ser, "AUTOSAR_SOMEIP"));

   SomeIpDeserializer des;
   someip_deserializer_init(&des, payloadBuf, ser.offset);

   uint8_t u8Val = 0;
   uint16_t u16Val = 0;
   uint32_t u32Val = 0;
   uint64_t u64Val = 0;
   float f32Val = 0.0f;
   double f64Val = 0.0;
   char strVal[64] = {0};

   assert(someip_deserialize_uint8(&des, &u8Val) && u8Val == 0xA5);
   assert(someip_deserialize_uint16(&des, &u16Val) && u16Val == 0x1234);
   assert(someip_deserialize_uint32(&des, &u32Val) && u32Val == 0xDEADBEEF);
   assert(someip_deserialize_uint64(&des, &u64Val) && u64Val == 0x0123456789ABCDEFULL);
   assert(someip_deserialize_float32(&des, &f32Val) && fabsf(f32Val - 123.456f) < 0.001f);
   assert(someip_deserialize_float64(&des, &f64Val) && fabs(f64Val - 98765.4321) < 0.0001);
   assert(someip_deserialize_string(&des, strVal, sizeof(strVal)) && strcmp(strVal, "AUTOSAR_SOMEIP") == 0);

   return true;
}

bool test_someip_service_discovery_offers_and_queries(void)
{
   SomeIpSdEngine engine;
   someip_sd_engine_init(&engine);

   uint8_t gwIp[4] = { 192, 168, 1, 10 };
   assert(someip_sd_engine_offer_service(&engine, 0x1000, 1, 1, 0, 300, gwIp, 30490, 0x11)); // UDP
   assert(someip_sd_engine_offer_service(&engine, 0x2000, 1, 2, 1, 600, gwIp, 30500, 0x06)); // TCP

   // 1. Build periodic offer announcement
   uint8_t offerPkt[512];
   uint32_t offerLen = someip_sd_engine_build_offers(&engine, offerPkt, sizeof(offerPkt));
   assert(offerLen > SOMEIP_HEADER_SIZE);

   SomeIpHeader offerHdr;
   assert(someip_header_decode(offerPkt, offerLen, &offerHdr));
   assert(offerHdr.serviceId == SOMEIP_SD_SERVICE_ID);
   assert(offerHdr.methodId == SOMEIP_SD_METHOD_ID);

   SomeIpSdMessage sdDecoded;
   assert(someip_sd_deserialize(offerPkt + SOMEIP_HEADER_SIZE, offerLen - SOMEIP_HEADER_SIZE, &sdDecoded));
   assert(sdDecoded.entryCount == 2);
   assert(sdDecoded.optionCount == 2);
   assert(sdDecoded.entries[0].serviceId == 0x1000);
   assert(sdDecoded.entries[1].serviceId == 0x2000);

   // 2. Client query with FindService (specific service 0x1000)
   SomeIpSdMessage findMsg;
   memset(&findMsg, 0, sizeof(SomeIpSdMessage));
   findMsg.flags = 0x80;
   findMsg.entryCount = 1;
   findMsg.entries[0].type = SOMEIP_SD_ENTRY_FIND_SERVICE;
   findMsg.entries[0].serviceId = 0x1000;
   findMsg.entries[0].instanceId = 0xFFFF; // Any instance
   findMsg.entries[0].majorVersion = 0xFF; // Any major version
   findMsg.entries[0].ttl = 30;

   uint8_t findPayload[256];
   uint32_t findPayloadLen = someip_sd_serialize(&findMsg, findPayload, sizeof(findPayload));

   SomeIpHeader findHdr;
   findHdr.serviceId = SOMEIP_SD_SERVICE_ID;
   findHdr.methodId  = SOMEIP_SD_METHOD_ID;
   findHdr.length    = findPayloadLen + 8;
   findHdr.clientId  = 0x1111;
   findHdr.sessionId = 0x0001;
   findHdr.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   findHdr.interfaceVersion = 0x01;
   findHdr.messageType      = SOMEIP_MSG_NOTIFICATION;
   findHdr.returnCode       = SOMEIP_RET_E_OK;

   uint8_t findWire[512];
   someip_header_encode(&findHdr, findWire, sizeof(findWire));
   memcpy(findWire + SOMEIP_HEADER_SIZE, findPayload, findPayloadLen);

   uint8_t respWire[512];
   uint32_t respWireLen = 0;
   assert(someip_sd_engine_process_sd_packet(&engine, findWire, SOMEIP_HEADER_SIZE + findPayloadLen, respWire, &respWireLen, sizeof(respWire)));

   SomeIpSdMessage findRespSd;
   assert(someip_sd_deserialize(respWire + SOMEIP_HEADER_SIZE, respWireLen - SOMEIP_HEADER_SIZE, &findRespSd));
   assert(findRespSd.entryCount == 1);
   assert(findRespSd.entries[0].serviceId == 0x1000);

   // 3. Client SubscribeEventgroup query
   SomeIpSdMessage subMsg;
   memset(&subMsg, 0, sizeof(SomeIpSdMessage));
   subMsg.flags = 0x80;
   subMsg.entryCount = 1;
   subMsg.entries[0].type = SOMEIP_SD_ENTRY_SUBSCRIBE_EVENTGROUP;
   subMsg.entries[0].serviceId = 0x1000;
   subMsg.entries[0].instanceId = 1;
   subMsg.entries[0].majorVersion = 1;
   subMsg.entries[0].ttl = 100;
   subMsg.entries[0].minorOrEventgroup = 0x0001; // Eventgroup 1

   uint8_t subPayload[256];
   uint32_t subPayloadLen = someip_sd_serialize(&subMsg, subPayload, sizeof(subPayload));
   someip_header_encode(&findHdr, findWire, sizeof(findWire));
   memcpy(findWire + SOMEIP_HEADER_SIZE, subPayload, subPayloadLen);

   assert(someip_sd_engine_process_sd_packet(&engine, findWire, SOMEIP_HEADER_SIZE + subPayloadLen, respWire, &respWireLen, sizeof(respWire)));

   SomeIpSdMessage subRespSd;
   assert(someip_sd_deserialize(respWire + SOMEIP_HEADER_SIZE, respWireLen - SOMEIP_HEADER_SIZE, &subRespSd));
   assert(subRespSd.entryCount == 1);
   assert(subRespSd.entries[0].type == SOMEIP_SD_ENTRY_SUBSCRIBE_EVENTGROUP_ACK);
   assert((subRespSd.entries[0].minorOrEventgroup & 0xFFFF) == 0x0001);
   assert(engine.subscriptionCount == 1);

   return true;
}

static bool rpc_get_speed(const SomeIpMessage* req, SomeIpMessage* resp)
{
   (void)req;
   SomeIpSerializer ser;
   someip_serializer_init(&ser, resp->payload, sizeof(resp->payload));
   someip_serialize_float32(&ser, 88.5f);
   resp->payloadLength = ser.offset;
   return true;
}

bool test_someip_rpc_dispatching_and_notifications(void)
{
   SomeIpRouter router;
   someip_router_init(&router);

   // Register method: Service 0x3000, Method 0x0001, InterfaceVer 1
   assert(someip_router_register_method(&router, 0x3000, 0x0001, 1, rpc_get_speed));

   // 1. Dispatch valid RPC request
   SomeIpMessage req;
   memset(&req, 0, sizeof(SomeIpMessage));
   req.header.serviceId        = 0x3000;
   req.header.methodId         = 0x0001;
   req.header.clientId         = 0x0001;
   req.header.sessionId        = 0x0010;
   req.header.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   req.header.interfaceVersion = 1;
   req.header.messageType      = SOMEIP_MSG_REQUEST;
   req.header.length           = 8;

   SomeIpMessage resp;
   assert(someip_router_dispatch(&router, &req, &resp));
   assert(resp.header.messageType == SOMEIP_MSG_RESPONSE);
   assert(resp.header.returnCode == SOMEIP_RET_E_OK);
   assert(resp.payloadLength == 4);

   SomeIpDeserializer des;
   someip_deserializer_init(&des, resp.payload, resp.payloadLength);
   float speed = 0.0f;
   assert(someip_deserialize_float32(&des, &speed));
   assert(fabsf(speed - 88.5f) < 0.01f);

   // 2. Reject unknown service
   req.header.serviceId = 0x9999;
   assert(someip_router_dispatch(&router, &req, &resp));
   assert(resp.header.returnCode == SOMEIP_RET_E_UNKNOWN_SERVICE);
   assert(resp.header.messageType == SOMEIP_MSG_ERROR);

   // 3. Reject unknown method
   req.header.serviceId = 0x3000;
   req.header.methodId  = 0x9999;
   assert(someip_router_dispatch(&router, &req, &resp));
   assert(resp.header.returnCode == SOMEIP_RET_E_UNKNOWN_METHOD);

   // 4. Reject interface version mismatch
   req.header.methodId         = 0x0001;
   req.header.interfaceVersion = 2; // Registered as 1
   assert(someip_router_dispatch(&router, &req, &resp));
   assert(resp.header.returnCode == SOMEIP_RET_E_WRONG_INTERFACE_VER);

   // 5. Test Event Notification publishing
   uint8_t eventPayload[4] = { 0xDE, 0xAD, 0xBE, 0xEF };
   uint8_t outBuf[64];
   uint32_t eventLen = someip_router_publish_event(&router, 0x3000, 0x0005, 1, eventPayload, sizeof(eventPayload), outBuf, sizeof(outBuf));
   assert(eventLen == SOMEIP_HEADER_SIZE + 4);

   SomeIpHeader evHdr;
   assert(someip_header_decode(outBuf, eventLen, &evHdr));
   assert(evHdr.serviceId == 0x3000);
   assert(evHdr.methodId == (0x8000 | 0x0005)); // High bit set for event
   assert(evHdr.messageType == SOMEIP_MSG_NOTIFICATION);
   assert(memcmp(outBuf + SOMEIP_HEADER_SIZE, eventPayload, 4) == 0);

   return true;
}
