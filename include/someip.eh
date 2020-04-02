// include/someip.eh
// AUTOSAR Scalable service-Oriented MiddlewarE over IP (SOME/IP) definitions.

#ifndef MANIFOLD_SOMEIP_EH
#define MANIFOLD_SOMEIP_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

// SOME/IP Message Types
typedef enum SomeIpMessageType
{
   SOMEIP_MSG_REQUEST               = 0x00,
   SOMEIP_MSG_REQUEST_NO_RETURN     = 0x01,
   SOMEIP_MSG_NOTIFICATION          = 0x02,
   SOMEIP_MSG_RESPONSE              = 0x80,
   SOMEIP_MSG_ERROR                 = 0x81,
   SOMEIP_MSG_TP_REQUEST            = 0x20,
   SOMEIP_MSG_TP_RESPONSE           = 0xA0
} SomeIpMessageType;

// SOME/IP Return Codes
typedef enum SomeIpReturnCode
{
   SOMEIP_RET_E_OK                  = 0x00,
   SOMEIP_RET_E_NOT_OK              = 0x01,
   SOMEIP_RET_E_UNKNOWN_SERVICE     = 0x02,
   SOMEIP_RET_E_UNKNOWN_METHOD      = 0x03,
   SOMEIP_RET_E_NOT_READY           = 0x04,
   SOMEIP_RET_E_NOT_REACHABLE       = 0x05,
   SOMEIP_RET_E_TIMEOUT             = 0x06,
   SOMEIP_RET_E_WRONG_PROTOCOL_VER  = 0x07,
   SOMEIP_RET_E_WRONG_INTERFACE_VER = 0x08,
   SOMEIP_RET_E_MALFORMED_MESSAGE   = 0x09,
   SOMEIP_RET_E_WRONG_MESSAGE_TYPE  = 0x0A
} SomeIpReturnCode;

// SOME/IP Header (16 bytes)
typedef struct SomeIpHeader
{
   uint16_t serviceId;
   uint16_t methodId;       // Or Event ID for notifications (bit 15 = 1)
   uint32_t length;         // Length of payload + 8 bytes (client ID to return code)
   uint16_t clientId;
   uint16_t sessionId;
   uint8_t protocolVersion; // Default 0x01
   uint8_t interfaceVersion;
   uint8_t messageType;
   uint8_t returnCode;
} SomeIpHeader;

// SOME/IP Message Container
typedef struct SomeIpMessage
{
   SomeIpHeader header;
   uint8_t payload[2048];
   uint32_t payloadLength;
} SomeIpMessage;

#endif // MANIFOLD_SOMEIP_EH
