// tests/integration/test_gateway_routing.ec
// Integration tests for Central Gateway routing, traffic shaping, DBC signals, CAN-SOME/IP bridge, and SecOC.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <math.h>

#include "types.eh"
#include "can.eh"
#include "routing.eh"
#include "dbc.eh"
#include "someip.eh"
#include "secoc.eh"
#include "ec_runtime.h"

// Forward declarations
bool test_gateway_routing_rules_and_translation(void);
bool test_traffic_shaper_burst_and_priority_egress(void);
bool test_dbc_signal_codec_intel_and_motorola(void);
bool test_cross_domain_can_someip_bridge_with_secoc(void);

bool test_gateway_routing_rules_and_translation(void)
{
   RoutingTable table;
   routing_table_init(&table);

   // Rule 1: Forward Powertrain 0x100 to Chassis bus (keep ID)
   assert(routing_table_add_rule(&table, BUS_DOMAIN_POWERTRAIN, 0x100, 0x7FF, BUS_DOMAIN_CHASSIS, 0x100, ROUTE_ACTION_FORWARD, 10));

   // Rule 2: Translate Powertrain 0x200 to Body bus 0x350
   assert(routing_table_add_rule(&table, BUS_DOMAIN_POWERTRAIN, 0x200, 0x7FF, BUS_DOMAIN_BODY, 0x350, ROUTE_ACTION_TRANSLATE_ID, 20));

   // Rule 3: Drop Powertrain 0x700 (Diagnostic broadcast filtered from Chassis)
   assert(routing_table_add_rule(&table, BUS_DOMAIN_POWERTRAIN, 0x700, 0x700, BUS_DOMAIN_CHASSIS, 0x000, ROUTE_ACTION_DROP, 50));

   // Test Case 1: 0x100 forwarded to Chassis
   CanFrame frame100;
   can_frame_init(&frame100, 0x100, false, false);
   uint8_t payload100[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
   can_frame_set_payload(&frame100, payload100, 8);

   BusDomain outDomain = BUS_DOMAIN_POWERTRAIN;
   CanFrame outFrame;
   assert(routing_table_route_frame(&table, BUS_DOMAIN_POWERTRAIN, &frame100, &outDomain, &outFrame));
   assert(outDomain == BUS_DOMAIN_CHASSIS);
   assert(outFrame.arbitrationId == 0x100);
   assert(memcmp(outFrame.data, payload100, 8) == 0);

   // Test Case 2: 0x200 translated to Body 0x350
   CanFrame frame200;
   can_frame_init(&frame200, 0x200, false, false);
   assert(routing_table_route_frame(&table, BUS_DOMAIN_POWERTRAIN, &frame200, &outDomain, &outFrame));
   assert(outDomain == BUS_DOMAIN_BODY);
   assert(outFrame.arbitrationId == 0x350);

   // Test Case 3: 0x700 dropped
   CanFrame frame700;
   can_frame_init(&frame700, 0x700, false, false);
   assert(!routing_table_route_frame(&table, BUS_DOMAIN_POWERTRAIN, &frame700, &outDomain, &outFrame));

   // Test Case 4: Unmatched frame dropped
   CanFrame frame999;
   can_frame_init(&frame999, 0x999, false, false);
   assert(!routing_table_route_frame(&table, BUS_DOMAIN_POWERTRAIN, &frame999, &outDomain, &outFrame));

   return true;
}

bool test_traffic_shaper_burst_and_priority_egress(void)
{
   // 1. Token Bucket Shaper Test
   TokenBucket bucket;
   traffic_shaper_init(&bucket, 1000, 1000); // 1000 capacity, 1000 tokens/sec refill

   assert(traffic_shaper_consume(&bucket, 800, 0)); // 200 remain
   assert(!traffic_shaper_consume(&bucket, 300, 0)); // Insufficient

   // Advance wall-clock by 500 ms -> refills 500 tokens (700 available)
   assert(traffic_shaper_consume(&bucket, 300, 500)); // 400 remain
   assert(traffic_shaper_consume(&bucket, 400, 500)); // 0 remain
   assert(!traffic_shaper_consume(&bucket, 10, 500));

   // 2. Priority Egress Queue Test
   EgressQueue queue;
   egress_queue_init(&queue);

   CanFrame frameLow, frameHigh, frameMed;
   can_frame_init(&frameLow, 0x300, false, false);
   can_frame_init(&frameMed, 0x200, false, false);
   can_frame_init(&frameHigh, 0x100, false, false);

   // Insert in random order: Low, High, Med
   assert(egress_queue_push(&queue, &frameLow, 1));
   assert(egress_queue_push(&queue, &frameHigh, 10));
   assert(egress_queue_push(&queue, &frameMed, 5));
   assert(queue.count == 3);

   // Strict Priority Pop order: High (10) -> Med (5) -> Low (1)
   CanFrame popped;
   assert(egress_queue_pop(&queue, &popped) && popped.arbitrationId == 0x100);
   assert(egress_queue_pop(&queue, &popped) && popped.arbitrationId == 0x200);
   assert(egress_queue_pop(&queue, &popped) && popped.arbitrationId == 0x300);
   assert(queue.count == 0);

   return true;
}

bool test_dbc_signal_codec_intel_and_motorola(void)
{
   DbcDatabase db;
   dbc_database_init(&db);

   // Define EngineStatus message: ID 0x100, 8 bytes DLC
   assert(dbc_database_add_message(&db, 0x100, "EngineStatus", 8, false));

   // Signal 1: EngineSpeed, startBit 0, length 16, Intel, factor 0.25, offset 0.0
   assert(dbc_database_add_signal(&db, 0x100, "EngineSpeed", 0, 16, ENDIAN_INTEL, false, 0.25, 0.0, 0.0, 8000.0, "rpm"));

   // Signal 2: CoolantTemp, startBit 16, length 8, Intel, unsigned, factor 1.0, offset -40.0
   assert(dbc_database_add_signal(&db, 0x100, "CoolantTemp", 16, 8, ENDIAN_INTEL, false, 1.0, -40.0, -40.0, 150.0, "degC"));

   // Signal 3: ThrottlePos, startBit 31, length 8, Motorola, factor 0.5, offset 0.0
   assert(dbc_database_add_signal(&db, 0x100, "ThrottlePos", 31, 8, ENDIAN_MOTOROLA, false, 0.5, 0.0, 0.0, 100.0, "%"));

   // Signal 4: SteeringAngle, startBit 32, length 16, Intel, signed, factor 0.1, offset 0.0
   assert(dbc_database_add_signal(&db, 0x100, "SteeringAngle", 32, 16, ENDIAN_INTEL, true, 0.1, 0.0, -720.0, 720.0, "deg"));

   const DbcMessage* msg = dbc_find_message(&db, 0x100);
   assert(msg != NULL && msg->signalCount == 4);

   const DbcSignal* sigSpeed  = dbc_find_signal(msg, "EngineSpeed");
   const DbcSignal* sigTemp   = dbc_find_signal(msg, "CoolantTemp");
   const DbcSignal* sigThrot  = dbc_find_signal(msg, "ThrottlePos");
   const DbcSignal* sigSteer  = dbc_find_signal(msg, "SteeringAngle");
   assert(sigSpeed && sigTemp && sigThrot && sigSteer);

   uint8_t payload[8] = {0};

   // Encode physical values: Speed = 2500.0 rpm, Coolant = 90.0 degC, Throttle = 75.0 %, Steering = -35.5 deg
   assert(dbc_encode_signal(sigSpeed, 2500.0, payload, sizeof(payload)));
   assert(dbc_encode_signal(sigTemp, 90.0, payload, sizeof(payload)));
   assert(dbc_encode_signal(sigThrot, 75.0, payload, sizeof(payload)));
   assert(dbc_encode_signal(sigSteer, -35.5, payload, sizeof(payload)));

   // Decode and verify physical accuracy
   double decSpeed = dbc_decode_signal(sigSpeed, payload, sizeof(payload));
   double decTemp  = dbc_decode_signal(sigTemp, payload, sizeof(payload));
   double decThrot = dbc_decode_signal(sigThrot, payload, sizeof(payload));
   double decSteer = dbc_decode_signal(sigSteer, payload, sizeof(payload));

   assert(fabs(decSpeed - 2500.0) < 0.25);
   assert(fabs(decTemp - 90.0) < 0.5);
   assert(fabs(decThrot - 75.0) < 0.5);
   assert(fabs(decSteer - (-35.5)) < 0.1);

   return true;
}

bool test_cross_domain_can_someip_bridge_with_secoc(void)
{
   // 1. Initialize SecOC Configuration
   SecOcConfig secConfig;
   secConfig.dataId = 0x1000;
   const uint8_t secretKey[16] = {
      0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
      0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
   };
   memcpy(secConfig.key, secretKey, 16);
   secConfig.macTruncationBits = 64; // 8 bytes MAC
   secConfig.freshnessBits = 64;

   // 2. Authentic payload: 8 bytes vehicle dynamics data
   uint8_t telemetry[8] = { 0x01, 0x02, 0x03, 0x04, 0xAA, 0xBB, 0xCC, 0xDD };
   uint64_t currentFreshness = 0x0000000000010001ULL;

   SecOcPdu securePdu;
   assert(secoc_secure_pdu(&secConfig, telemetry, sizeof(telemetry), currentFreshness, &securePdu));
   assert(secoc_verify_pdu(&secConfig, &securePdu));

   // Verify MAC tampering detection
   securePdu.payload[0] ^= 0x01; // Tamper 1 bit
   assert(!secoc_verify_pdu(&secConfig, &securePdu));
   securePdu.payload[0] ^= 0x01; // Restore
   assert(secoc_verify_pdu(&secConfig, &securePdu));

   // 3. Encapsulate into CAN FD frame (8 bytes data + 8 bytes MAC = 16 bytes)
   CanFrame ingressCanFd;
   can_frame_init(&ingressCanFd, 0x120, false, true);
   uint8_t combinedCanData[16];
   memcpy(combinedCanData, securePdu.payload, 8);
   memcpy(combinedCanData + 8, securePdu.mac, 8);
   can_frame_set_payload(&ingressCanFd, combinedCanData, 16);

   // 4. Bridge to SOME/IP Notification
   CanSomeipBridge bridge;
   bridge_init(&bridge, 0x120, 0x4000, 0x0001, 1);

   SomeIpMessage egressSomeip;
   assert(bridge_can_to_someip(&bridge, &ingressCanFd, &egressSomeip));
   assert(egressSomeip.header.serviceId == 0x4000);
   assert(egressSomeip.header.methodId == 0x8001); // Event notification high bit
   assert(egressSomeip.payloadLength == 16);
   assert(memcmp(egressSomeip.payload, combinedCanData, 16) == 0);

   // 5. Reverse Bridge: SOME/IP back to CAN FD frame
   CanFrame routedCanFd;
   assert(bridge_someip_to_can(&bridge, &egressSomeip, &routedCanFd));
   assert(routedCanFd.arbitrationId == 0x120);
   assert(routedCanFd.payloadLength == 16);
   assert(routedCanFd.flags.isFd);
   assert(memcmp(routedCanFd.data, combinedCanData, 16) == 0);

   return true;
}
