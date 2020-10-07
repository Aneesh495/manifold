// src/app/Simulator.ec
// Multi-ECU in-vehicle network simulator for powertrain, chassis, body, and ADAS domains.

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#include "types.eh"
#include "can.eh"
#include "routing.eh"
#include "dbc.eh"
#include "someip.eh"
#include "secoc.eh"
#include "uds.eh"
#include "doip.eh"
#include "xcp.eh"
#include "ec_runtime.h"

// Initializes the virtual multi-ECU vehicle simulator and routing gateway
void simulator_init(VehicleSimulator* sim)
{
   if(!sim) return;
   memset(sim, 0, sizeof(VehicleSimulator));

   sim->simulatedTimeMs   = 0;
   sim->engineRpm         = 850.0;  // Idle RPM
   sim->vehicleSpeedKph   = 0.0;
   sim->coolantTempC      = 88.0;
   sim->throttlePercent   = 15.0;
   sim->steeringAngleDeg  = 0.0;
   sim->brakeActive       = false;

   // 1. Configure Gateway Routing Table
   routing_table_init(&sim->routingTable);
   // Route ECM 0x100 to Chassis domain (forward)
   routing_table_add_rule(&sim->routingTable, BUS_DOMAIN_POWERTRAIN, 0x100, 0x7FF, BUS_DOMAIN_CHASSIS, 0x100, ROUTE_ACTION_FORWARD, 10);
   // Route Chassis 0x120 to Body domain (translate to 0x350)
   routing_table_add_rule(&sim->routingTable, BUS_DOMAIN_CHASSIS, 0x120, 0x7FF, BUS_DOMAIN_BODY, 0x350, ROUTE_ACTION_TRANSLATE_ID, 20);

   // 2. Configure Token Bucket Traffic Shaper (2000 bytes/sec, 500 byte burst)
   traffic_shaper_init(&sim->powertrainShaper, 500, 2000);

   // 3. Configure CAN FD to SOME/IP Semantic Bridge
   bridge_init(&sim->powertrainBridge, 0x100, 0x2000, 0x0001, 1);

   // 4. Configure SecOC Security Parameters
   const uint8_t aesKey[16] = {
      0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
      0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
   };
   memcpy(sim->secocKey, aesKey, 16);
   sim->secocFreshness = 1;
}

// Executes a discrete simulation step of length stepMs
void simulator_step(VehicleSimulator* sim, uint32_t stepMs)
{
   if(!sim) return;

   sim->simulatedTimeMs += stepMs;
   sim->stepCount++;

   // Simulate vehicle physics: accelerate up to 110 kph, then decelerate
   if(sim->vehicleSpeedKph < 110.0 && !sim->brakeActive)
   {
      sim->throttlePercent = 45.0;
      sim->engineRpm += 35.0;
      sim->vehicleSpeedKph += 0.8;
      sim->coolantTempC = 90.0 + (sim->engineRpm / 5000.0) * 5.0;
      if(sim->vehicleSpeedKph >= 110.0) sim->brakeActive = true;
   }
   else
   {
      sim->throttlePercent = 0.0;
      sim->engineRpm -= 50.0;
      sim->vehicleSpeedKph -= 1.2;
      if(sim->vehicleSpeedKph <= 20.0) sim->brakeActive = false;
   }

   // 1. ECM Node: Broadcasts CAN FD 0x100 EngineStatus (16 bytes)
   CanFrame ecmFrame;
   can_frame_init(&ecmFrame, 0x100, false, true);
   uint8_t ecmPayload[16] = {0};

   uint16_t rawRpm = (uint16_t)llround(sim->engineRpm * 4.0);
   ecmPayload[0] = (uint8_t)(rawRpm & 0xFF);
   ecmPayload[1] = (uint8_t)((rawRpm >> 8) & 0xFF);
   ecmPayload[2] = (uint8_t)llround(sim->coolantTempC + 40.0);
   ecmPayload[3] = (uint8_t)llround(sim->throttlePercent * 2.0);

   // Authenticate payload using SecOC
   SecOcConfig cfg;
   cfg.dataId = 0x1000;
   memcpy(cfg.key, sim->secocKey, 16);
   cfg.macTruncationBits = 64;
   cfg.freshnessBits = 64;

   SecOcPdu securedEcm;
   secoc_secure_pdu(&cfg, ecmPayload, 8, sim->secocFreshness++, &securedEcm);
   memcpy(ecmPayload + 8, securedEcm.mac, 8); // Append 8-byte CMAC
   can_frame_set_payload(&ecmFrame, ecmPayload, 16);

   // 2. Gateway Ingress Rate Limiting and Routing
   if(traffic_shaper_consume(&sim->powertrainShaper, 16, sim->simulatedTimeMs))
   {
      BusDomain egressDomain;
      CanFrame routedFrame;
      if(routing_table_route_frame(&sim->routingTable, BUS_DOMAIN_POWERTRAIN, &ecmFrame, &egressDomain, &routedFrame))
      {
         sim->framesRoutedPowertrain++;
         if(egressDomain == BUS_DOMAIN_CHASSIS)
         {
            sim->framesRoutedChassis++;
         }
      }

      // 3. Gateway Cross-Domain SOME/IP Bridge Repackaging
      SomeIpMessage bridgedSomeip;
      if(bridge_can_to_someip(&sim->powertrainBridge, &ecmFrame, &bridgedSomeip))
      {
         sim->someipMessagesPublished++;
      }
   }
}

// Prints formatted live simulation and gateway metrics
void simulator_print_metrics(const VehicleSimulator* sim)
{
   if(!sim) return;

   printf("------------------------------------------------------------------\n");
   printf(" Time: %6llu ms | Steps: %5u | Speed: %5.1f km/h | RPM: %6.1f\n",
          (unsigned long long)sim->simulatedTimeMs, sim->stepCount, sim->vehicleSpeedKph, sim->engineRpm);
   printf(" Coolant: %5.1f C | Throttle: %4.1f %% | Brake: %s\n",
          sim->coolantTempC, sim->throttlePercent, sim->brakeActive ? "ACTIVE" : "OFF");
   printf(" Gateway Stats: PWT Routed=%llu, Chassis Routed=%llu, SOME/IP Pub=%llu\n",
          (unsigned long long)sim->framesRoutedPowertrain,
          (unsigned long long)sim->framesRoutedChassis,
          (unsigned long long)sim->someipMessagesPublished);
   printf("------------------------------------------------------------------\n");
}
