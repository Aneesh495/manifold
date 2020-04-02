// include/doip.eh
// ISO 13400-2 Diagnostic over IP (DoIP) message definitions and session manager.

#ifndef MANIFOLD_DOIP_EH
#define MANIFOLD_DOIP_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define DOIP_PROTOCOL_VERSION 0x02
#define DOIP_DEFAULT_TCP_PORT 13400
#define DOIP_DEFAULT_UDP_PORT 13400

// DoIP Payload Types
typedef enum DoipPayloadType
{
   DOIP_TYPE_GENERIC_NACK                        = 0x0000,
   DOIP_TYPE_VEHICLE_IDENT_REQUEST               = 0x0001,
   DOIP_TYPE_VEHICLE_IDENT_REQUEST_EID           = 0x0002,
   DOIP_TYPE_VEHICLE_IDENT_REQUEST_VIN           = 0x0003,
   DOIP_TYPE_VEHICLE_ANNOUNCEMENT_MESSAGE        = 0x0004,
   DOIP_TYPE_ROUTING_ACTIVATION_REQUEST          = 0x0005,
   DOIP_TYPE_ROUTING_ACTIVATION_RESPONSE         = 0x0006,
   DOIP_TYPE_ALIVE_CHECK_REQUEST                 = 0x0007,
   DOIP_TYPE_ALIVE_CHECK_RESPONSE                = 0x0008,
   DOIP_TYPE_ENTITY_STATUS_REQUEST               = 0x4001,
   DOIP_TYPE_ENTITY_STATUS_RESPONSE              = 0x4002,
   DOIP_TYPE_DIAGNOSTIC_MESSAGE                  = 0x8001,
   DOIP_TYPE_DIAGNOSTIC_POSITIVE_ACK             = 0x8002,
   DOIP_TYPE_DIAGNOSTIC_NEGATIVE_ACK             = 0x8003
} DoipPayloadType;

// Routing Activation Response Codes
typedef enum DoipRoutingActivationResponse
{
   DOIP_ROUTING_SUCCESS                          = 0x10,
   DOIP_ROUTING_ERR_UNKNOWN_SA                   = 0x00,
   DOIP_ROUTING_ERR_ALL_SOCKETS_REGISTERED       = 0x01,
   DOIP_ROUTING_ERR_SA_DIFFERENT                 = 0x02,
   DOIP_ROUTING_ERR_SA_ALREADY_REGISTERED        = 0x03,
   DOIP_ROUTING_ERR_MISSING_AUTHENTICATION       = 0x04,
   DOIP_ROUTING_ERR_REJECTED_CONFIRMATION        = 0x05,
   DOIP_ROUTING_ERR_UNSUPPORTED_TYPE             = 0x06
} DoipRoutingActivationResponse;

// DoIP Generic Header
typedef struct DoipHeader
{
   uint8_t protocolVersion;
   uint8_t inverseVersion;
   uint16_t payloadType;
   uint32_t payloadLength;
} DoipHeader;

// DoIP Client Session
typedef struct DoipSession
{
   uint16_t clientLogicalAddress;
   bool isActivated;
   uint64_t lastAliveCheckMs;
   uint32_t connectionId;
} DoipSession;

#endif // MANIFOLD_DOIP_EH
