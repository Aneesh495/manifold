// src/routing/BridgeCanSomeip.ec
// Semantic cross-domain bridge between CAN/CAN FD signal PDUs and AUTOSAR SOME/IP messages.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "someip.eh"
#include "routing.eh"
#include "ec_runtime.h"

// Initializes a CAN FD to SOME/IP mapping bridge
void bridge_init(CanSomeipBridge* bridge, uint32_t canId, uint16_t serviceId, uint16_t methodOrEventId, uint8_t interfaceVer)
{
   if(!bridge) return;
   bridge->canId            = canId;
   bridge->serviceId        = serviceId;
   bridge->methodOrEventId  = methodOrEventId;
   bridge->interfaceVersion = interfaceVer;
}

// Repackages a CAN/CAN FD frame into a serialized SOME/IP notification message
bool bridge_can_to_someip(const CanSomeipBridge* bridge, const CanFrame* frame, SomeIpMessage* outSomeip)
{
   if(!bridge || !frame || !outSomeip)
   {
      return false;
   }

   if(frame->arbitrationId != bridge->canId)
   {
      return false; // CAN ID does not match bridge configuration
   }

   uint32_t payloadLen = frame->payloadLength;
   if(payloadLen > SOMEIP_PAYLOAD_MAX)
   {
      return false;
   }

   memset(outSomeip, 0, sizeof(SomeIpMessage));
   outSomeip->header.serviceId        = bridge->serviceId;
   outSomeip->header.methodId         = (bridge->methodOrEventId | 0x8000); // Event high bit
   outSomeip->header.length           = payloadLen + 8;
   outSomeip->header.clientId         = 0x0000;
   outSomeip->header.sessionId        = 0x0001;
   outSomeip->header.protocolVersion  = SOMEIP_PROTOCOL_VERSION;
   outSomeip->header.interfaceVersion = bridge->interfaceVersion;
   outSomeip->header.messageType      = SOMEIP_MSG_NOTIFICATION;
   outSomeip->header.returnCode       = SOMEIP_RET_E_OK;

   memcpy(outSomeip->payload, frame->data, payloadLen);
   outSomeip->payloadLength = payloadLen;

   return true;
}

// Repackages a SOME/IP event message into an egress CAN/CAN FD frame
bool bridge_someip_to_can(const CanSomeipBridge* bridge, const SomeIpMessage* msg, CanFrame* outFrame)
{
   if(!bridge || !msg || !outFrame)
   {
      return false;
   }

   if(msg->header.serviceId != bridge->serviceId)
   {
      return false;
   }

   uint32_t copyLen = msg->payloadLength;
   if(copyLen > CAN_FD_MAX_DATA_LEN)
   {
      copyLen = CAN_FD_MAX_DATA_LEN;
   }

   can_frame_init(outFrame, bridge->canId, false, (copyLen > 8));
   can_frame_set_payload(outFrame, msg->payload, (uint8_t)copyLen);

   return true;
}
