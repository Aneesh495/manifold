// src/someip/SomeIpSdEngine.ec
// AUTOSAR SOME/IP-SD state engine for Service Offers, Find Service queries, and Eventgroup Subscriptions.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "someip.eh"
#include "ec_runtime.h"

// Initializes the SOME/IP Service Discovery engine
void someip_sd_engine_init(SomeIpSdEngine* engine)
{
   if(!engine) return;
   memset(engine, 0, sizeof(SomeIpSdEngine));
}

// Registers a service offer in the local SD registry
bool someip_sd_engine_offer_service(SomeIpSdEngine* engine, uint16_t serviceId, uint16_t instanceId, uint8_t majorVer, uint32_t minorVer, uint32_t ttl, const uint8_t* ipv4, uint16_t port, uint8_t protocol)
{
   if(!engine || !ipv4) return false;

   // Check if this service instance already exists; if so, refresh it
   for(uint32_t i = 0; i < engine->offerCount; i++)
   {
      if(engine->offers[i].serviceId == serviceId && engine->offers[i].instanceId == instanceId)
      {
         engine->offers[i].majorVersion = majorVer;
         engine->offers[i].minorVersion = minorVer;
         engine->offers[i].ttl          = ttl;
         memcpy(engine->offers[i].ipv4, ipv4, 4);
         engine->offers[i].port         = port;
         engine->offers[i].protocol     = protocol;
         engine->offers[i].active       = true;
         return true;
      }
   }

   if(engine->offerCount >= SOMEIP_MAX_OFFERS)
   {
      return false;
   }

   SomeIpServiceOffer* offer = &engine->offers[engine->offerCount++];
   offer->serviceId    = serviceId;
   offer->instanceId   = instanceId;
   offer->majorVersion = majorVer;
   offer->minorVersion = minorVer;
   offer->ttl          = ttl;
   memcpy(offer->ipv4, ipv4, 4);
   offer->port         = port;
   offer->protocol     = protocol;
   offer->active       = true;

   return true;
}

// Stops offering a service instance by deactivating its registry entry
bool someip_sd_engine_stop_offer_service(SomeIpSdEngine* engine, uint16_t serviceId, uint16_t instanceId)
{
   if(!engine) return false;

   for(uint32_t i = 0; i < engine->offerCount; i++)
   {
      if(engine->offers[i].serviceId == serviceId && engine->offers[i].instanceId == instanceId && engine->offers[i].active)
      {
         engine->offers[i].active = false;
         return true;
      }
   }
   return false;
}

// Builds a complete wire SOME/IP-SD Offer Service packet containing all active offers
uint32_t someip_sd_engine_build_offers(const SomeIpSdEngine* engine, uint8_t* outBuf, uint32_t maxLen)
{
   if(!engine || !outBuf || maxLen < (SOMEIP_HEADER_SIZE + 32))
   {
      return 0;
   }

   SomeIpSdMessage sdMsg;
   memset(&sdMsg, 0, sizeof(SomeIpSdMessage));
   sdMsg.flags = 0x80; // Reboot flag = 1

   for(uint32_t i = 0; i < engine->offerCount; i++)
   {
      if(!engine->offers[i].active) continue;
      if(sdMsg.entryCount >= SOMEIP_SD_MAX_ENTRIES || sdMsg.optionCount >= SOMEIP_SD_MAX_OPTIONS) break;

      uint32_t entryIdx = sdMsg.entryCount++;
      uint32_t optIdx   = sdMsg.optionCount++;

      SomeIpSdEntry* e = &sdMsg.entries[entryIdx];
      e->type           = SOMEIP_SD_ENTRY_OFFER_SERVICE;
      e->index1         = (uint8_t)optIdx;
      e->index2         = 0;
      e->numOptions     = 0x10; // 1 option in 1st run
      e->serviceId      = engine->offers[i].serviceId;
      e->instanceId     = engine->offers[i].instanceId;
      e->majorVersion   = engine->offers[i].majorVersion;
      e->ttl            = engine->offers[i].ttl;
      e->minorOrEventgroup = engine->offers[i].minorVersion;

      SomeIpSdOption* opt = &sdMsg.options[optIdx];
      opt->type         = SOMEIP_SD_OPT_IPV4_ENDPOINT;
      memcpy(opt->ipv4, engine->offers[i].ipv4, 4);
      opt->protocol     = engine->offers[i].protocol;
      opt->port         = engine->offers[i].port;
   }

   if(sdMsg.entryCount == 0)
   {
      return 0;
   }

   uint8_t sdPayload[SOMEIP_PAYLOAD_MAX];
   uint32_t sdPayloadLen = someip_sd_serialize(&sdMsg, sdPayload, sizeof(sdPayload));
   if(sdPayloadLen == 0 || maxLen < (SOMEIP_HEADER_SIZE + sdPayloadLen))
   {
      return 0;
   }

   SomeIpHeader hdr;
   hdr.serviceId        = SOMEIP_SD_SERVICE_ID;
   hdr.methodId         = SOMEIP_SD_METHOD_ID;
   hdr.length           = sdPayloadLen + 8;
   hdr.clientId         = SOMEIP_SD_CLIENT_ID;
   hdr.sessionId        = 0x0001;
   hdr.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   hdr.interfaceVersion = 0x01;
   hdr.messageType      = SOMEIP_MSG_NOTIFICATION;
   hdr.returnCode       = SOMEIP_RET_E_OK;

   if(!someip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   memcpy(outBuf + SOMEIP_HEADER_SIZE, sdPayload, sdPayloadLen);
   return SOMEIP_HEADER_SIZE + sdPayloadLen;
}

// Processes an incoming SOME/IP-SD packet (e.g. FindService or SubscribeEventgroup)
// and formulates appropriate OfferService or SubscribeEventgroupAck response.
bool someip_sd_engine_process_sd_packet(SomeIpSdEngine* engine, const uint8_t* inBuf, uint32_t inLen, uint8_t* outResponse, uint32_t* outRespLen, uint32_t maxRespLen)
{
   if(!engine || !inBuf || !outResponse || !outRespLen || inLen < SOMEIP_HEADER_SIZE)
   {
      return false;
   }

   SomeIpHeader inHdr;
   if(!someip_header_decode(inBuf, inLen, &inHdr))
   {
      return false;
   }

   if(inHdr.serviceId != SOMEIP_SD_SERVICE_ID || inHdr.methodId != SOMEIP_SD_METHOD_ID)
   {
      return false;
   }

   SomeIpSdMessage inSd;
   if(!someip_sd_deserialize(inBuf + SOMEIP_HEADER_SIZE, inLen - SOMEIP_HEADER_SIZE, &inSd))
   {
      return false;
   }

   SomeIpSdMessage respSd;
   memset(&respSd, 0, sizeof(SomeIpSdMessage));
   respSd.flags = 0x80;

   for(uint32_t i = 0; i < inSd.entryCount; i++)
   {
      const SomeIpSdEntry* inEntry = &inSd.entries[i];

      // Case A: FindService query
      if(inEntry->type == SOMEIP_SD_ENTRY_FIND_SERVICE)
      {
         for(uint32_t o = 0; o < engine->offerCount; o++)
         {
            if(!engine->offers[o].active) continue;
            // Match specific service ID or wildcard 0xFFFF
            if(inEntry->serviceId == 0xFFFF || inEntry->serviceId == engine->offers[o].serviceId)
            {
               if(respSd.entryCount < SOMEIP_SD_MAX_ENTRIES && respSd.optionCount < SOMEIP_SD_MAX_OPTIONS)
               {
                  uint32_t entryIdx = respSd.entryCount++;
                  uint32_t optIdx   = respSd.optionCount++;

                  SomeIpSdEntry* e = &respSd.entries[entryIdx];
                  e->type           = SOMEIP_SD_ENTRY_OFFER_SERVICE;
                  e->index1         = (uint8_t)optIdx;
                  e->index2         = 0;
                  e->numOptions     = 0x10;
                  e->serviceId      = engine->offers[o].serviceId;
                  e->instanceId     = engine->offers[o].instanceId;
                  e->majorVersion   = engine->offers[o].majorVersion;
                  e->ttl            = engine->offers[o].ttl;
                  e->minorOrEventgroup = engine->offers[o].minorVersion;

                  SomeIpSdOption* opt = &respSd.options[optIdx];
                  opt->type         = SOMEIP_SD_OPT_IPV4_ENDPOINT;
                  memcpy(opt->ipv4, engine->offers[o].ipv4, 4);
                  opt->protocol     = engine->offers[o].protocol;
                  opt->port         = engine->offers[o].port;
               }
            }
         }
      }
      // Case B: SubscribeEventgroup
      else if(inEntry->type == SOMEIP_SD_ENTRY_SUBSCRIBE_EVENTGROUP)
      {
         uint16_t eventgroupId = (uint16_t)(inEntry->minorOrEventgroup & 0xFFFF);
         uint8_t subIpv4[4] = { 127, 0, 0, 1 };
         uint16_t subPort = 30490;

         // Extract subscriber endpoint from options if provided
         if(inEntry->index1 < inSd.optionCount)
         {
            memcpy(subIpv4, inSd.options[inEntry->index1].ipv4, 4);
            subPort = inSd.options[inEntry->index1].port;
         }

         // Record subscription in engine
         if(engine->subscriptionCount < SOMEIP_MAX_SUBSCRIPTIONS)
         {
            SomeIpSubscription* sub = &engine->subscriptions[engine->subscriptionCount++];
            sub->serviceId = inEntry->serviceId;
            sub->instanceId = inEntry->instanceId;
            sub->eventgroupId = eventgroupId;
            sub->ttl = inEntry->ttl;
            memcpy(sub->subscriberIpv4, subIpv4, 4);
            sub->subscriberPort = subPort;
            sub->active = true;
         }

         // Acknowledge subscription
         if(respSd.entryCount < SOMEIP_SD_MAX_ENTRIES)
         {
            uint32_t entryIdx = respSd.entryCount++;
            SomeIpSdEntry* e = &respSd.entries[entryIdx];
            e->type           = SOMEIP_SD_ENTRY_SUBSCRIBE_EVENTGROUP_ACK;
            e->index1         = 0;
            e->index2         = 0;
            e->numOptions     = 0;
            e->serviceId      = inEntry->serviceId;
            e->instanceId     = inEntry->instanceId;
            e->majorVersion   = inEntry->majorVersion;
            e->ttl            = inEntry->ttl;
            e->minorOrEventgroup = eventgroupId;
         }
      }
   }

   if(respSd.entryCount == 0)
   {
      *outRespLen = 0;
      return false;
   }

   uint8_t sdPayload[SOMEIP_PAYLOAD_MAX];
   uint32_t sdPayloadLen = someip_sd_serialize(&respSd, sdPayload, sizeof(sdPayload));
   if(sdPayloadLen == 0 || maxRespLen < (SOMEIP_HEADER_SIZE + sdPayloadLen))
   {
      *outRespLen = 0;
      return false;
   }

   SomeIpHeader respHdr;
   respHdr.serviceId        = SOMEIP_SD_SERVICE_ID;
   respHdr.methodId         = SOMEIP_SD_METHOD_ID;
   respHdr.length           = sdPayloadLen + 8;
   respHdr.clientId         = SOMEIP_SD_CLIENT_ID;
   respHdr.sessionId        = inHdr.sessionId;
   respHdr.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   respHdr.interfaceVersion = 0x01;
   respHdr.messageType      = SOMEIP_MSG_NOTIFICATION;
   respHdr.returnCode       = SOMEIP_RET_E_OK;

   if(!someip_header_encode(&respHdr, outResponse, maxRespLen))
   {
      *outRespLen = 0;
      return false;
   }

   memcpy(outResponse + SOMEIP_HEADER_SIZE, sdPayload, sdPayloadLen);
   *outRespLen = SOMEIP_HEADER_SIZE + sdPayloadLen;

   return true;
}
