// src/someip/SomeIpRouter.ec
// AUTOSAR SOME/IP RPC method dispatcher and asynchronous event notification publisher.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "someip.eh"
#include "ec_runtime.h"

// Initializes the SOME/IP RPC router
void someip_router_init(SomeIpRouter* router)
{
   if(!router) return;
   memset(router, 0, sizeof(SomeIpRouter));
   router->nextSessionId = 1;
}

// Registers an RPC method handler for a specific service and method ID
bool someip_router_register_method(SomeIpRouter* router, uint16_t serviceId, uint16_t methodId, uint8_t interfaceVer, SomeIpMethodHandler handler)
{
   if(!router || !handler || router->methodCount >= SOMEIP_MAX_RPC_METHODS)
   {
      return false;
   }

   SomeIpMethodEntry* entry = &router->methods[router->methodCount++];
   entry->serviceId        = serviceId;
   entry->methodId         = methodId;
   entry->interfaceVersion = interfaceVer;
   entry->handler          = handler;

   return true;
}

// Dispatches an incoming SOME/IP request to the registered RPC handler
bool someip_router_dispatch(SomeIpRouter* router, const SomeIpMessage* req, SomeIpMessage* resp)
{
   if(!router || !req || !resp)
   {
      return false;
   }

   // Validate request message types
   if(req->header.messageType != SOMEIP_MSG_REQUEST &&
      req->header.messageType != SOMEIP_MSG_REQUEST_NO_RETURN)
   {
      someip_message_init_response(req, resp, SOMEIP_RET_E_WRONG_MESSAGE_TYPE);
      return true;
   }

   // Protocol version verification
   if(req->header.protocolVersion != SOMEIP_PROTOCOL_VERSION)
   {
      someip_message_init_response(req, resp, SOMEIP_RET_E_WRONG_PROTOCOL_VER);
      return true;
   }

   // Check if service exists
   bool serviceFound = false;
   const SomeIpMethodEntry* matchedMethod = NULL;

   for(uint32_t i = 0; i < router->methodCount; i++)
   {
      if(router->methods[i].serviceId == req->header.serviceId)
      {
         serviceFound = true;
         if(router->methods[i].methodId == req->header.methodId)
         {
            matchedMethod = &router->methods[i];
            break;
         }
      }
   }

   if(!serviceFound)
   {
      someip_message_init_response(req, resp, SOMEIP_RET_E_UNKNOWN_SERVICE);
      return true;
   }

   if(!matchedMethod)
   {
      someip_message_init_response(req, resp, SOMEIP_RET_E_UNKNOWN_METHOD);
      return true;
   }

   // Check interface version compatibility
   if(req->header.interfaceVersion != matchedMethod->interfaceVersion)
   {
      someip_message_init_response(req, resp, SOMEIP_RET_E_WRONG_INTERFACE_VER);
      return true;
   }

   // Initialize base positive response
   someip_message_init_response(req, resp, SOMEIP_RET_E_OK);

   // Invoke application RPC handler
   bool handled = matchedMethod->handler(req, resp);
   if(!handled)
   {
      resp->header.returnCode = SOMEIP_RET_E_NOT_OK;
      resp->header.messageType = SOMEIP_MSG_ERROR;
   }

   // If the original request was fire-and-forget (REQUEST_NO_RETURN), suppress response
   if(req->header.messageType == SOMEIP_MSG_REQUEST_NO_RETURN)
   {
      return false;
   }

   return true;
}

// Publishes an asynchronous SOME/IP event notification to subscribed consumers
uint32_t someip_router_publish_event(SomeIpRouter* router, uint16_t serviceId, uint16_t eventId, uint8_t interfaceVer, const uint8_t* data, uint32_t dataLen, uint8_t* outBuf, uint32_t maxLen)
{
   if(!router || !outBuf || (SOMEIP_HEADER_SIZE + dataLen) > maxLen)
   {
      return 0;
   }

   // AUTOSAR convention: Event IDs have high bit 15 set (0x8000 | eventId)
   uint16_t wireEventId = (eventId | 0x8000);

   SomeIpHeader hdr;
   hdr.serviceId        = serviceId;
   hdr.methodId         = wireEventId;
   hdr.length           = dataLen + 8;
   hdr.clientId         = 0x0000;
   hdr.sessionId        = router->nextSessionId++;
   hdr.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   hdr.interfaceVersion = interfaceVer;
   hdr.messageType      = SOMEIP_MSG_NOTIFICATION;
   hdr.returnCode       = SOMEIP_RET_E_OK;

   if(!someip_header_encode(&hdr, outBuf, maxLen))
   {
      return 0;
   }

   if(data && dataLen > 0)
   {
      memcpy(outBuf + SOMEIP_HEADER_SIZE, data, dataLen);
   }

   return SOMEIP_HEADER_SIZE + dataLen;
}
