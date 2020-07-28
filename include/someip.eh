// include/someip.eh
// AUTOSAR Scalable service-Oriented MiddlewarE over IP (SOME/IP) definitions.

#ifndef MANIFOLD_SOMEIP_EH
#define MANIFOLD_SOMEIP_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define SOMEIP_HEADER_SIZE             16
#define SOMEIP_PROTOCOL_VERSION        0x01
#define SOMEIP_PAYLOAD_MAX             4096

// SOME/IP-SD Well-Known Identifiers
#define SOMEIP_SD_SERVICE_ID           0xFFFF
#define SOMEIP_SD_METHOD_ID            0x8100
#define SOMEIP_SD_CLIENT_ID            0x0000

// SOME/IP Message Types (AUTOSAR PRS_SOMEIP_00055)
typedef enum SomeIpMessageType
{
   SOMEIP_MSG_REQUEST                  = 0x00,
   SOMEIP_MSG_REQUEST_NO_RETURN        = 0x01,
   SOMEIP_MSG_NOTIFICATION             = 0x02,
   SOMEIP_MSG_RESPONSE                 = 0x80,
   SOMEIP_MSG_ERROR                    = 0x81,
   SOMEIP_MSG_TP_REQUEST               = 0x20,
   SOMEIP_MSG_TP_RESPONSE              = 0xA0
} SomeIpMessageType;

// SOME/IP Return Codes (AUTOSAR PRS_SOMEIP_00191)
typedef enum SomeIpReturnCode
{
   SOMEIP_RET_E_OK                     = 0x00,
   SOMEIP_RET_E_NOT_OK                 = 0x01,
   SOMEIP_RET_E_UNKNOWN_SERVICE        = 0x02,
   SOMEIP_RET_E_UNKNOWN_METHOD         = 0x03,
   SOMEIP_RET_E_NOT_READY              = 0x04,
   SOMEIP_RET_E_NOT_REACHABLE          = 0x05,
   SOMEIP_RET_E_TIMEOUT                = 0x06,
   SOMEIP_RET_E_WRONG_PROTOCOL_VER     = 0x07,
   SOMEIP_RET_E_WRONG_INTERFACE_VER    = 0x08,
   SOMEIP_RET_E_MALFORMED_MESSAGE      = 0x09,
   SOMEIP_RET_E_WRONG_MESSAGE_TYPE     = 0x0A
} SomeIpReturnCode;

// SOME/IP Header (16 bytes wire format)
typedef struct SomeIpHeader
{
   uint16_t serviceId;
   uint16_t methodId;       // Bit 15: 0 for Method, 1 for Event/Notification
   uint32_t length;         // Length of payload + 8 bytes (from client ID to end)
   uint16_t clientId;
   uint16_t sessionId;
   uint8_t protocolVersion; // Typically 0x01
   uint8_t interfaceVersion;
   uint8_t messageType;
   uint8_t returnCode;
} SomeIpHeader;

// SOME/IP Message Container
typedef struct SomeIpMessage
{
   SomeIpHeader header;
   uint8_t payload[SOMEIP_PAYLOAD_MAX];
   uint32_t payloadLength;
} SomeIpMessage;

// Serialization Helpers
typedef struct SomeIpSerializer
{
   uint8_t* buffer;
   uint32_t capacity;
   uint32_t offset;
} SomeIpSerializer;

typedef struct SomeIpDeserializer
{
   const uint8_t* buffer;
   uint32_t length;
   uint32_t offset;
} SomeIpDeserializer;

// SOME/IP-SD Entry Types
typedef enum SomeIpSdEntryType
{
   SOMEIP_SD_ENTRY_FIND_SERVICE               = 0x00,
   SOMEIP_SD_ENTRY_OFFER_SERVICE              = 0x01,
   SOMEIP_SD_ENTRY_STOP_OFFER_SERVICE         = 0x01, // Differentiated by TTL = 0
   SOMEIP_SD_ENTRY_SUBSCRIBE_EVENTGROUP       = 0x06,
   SOMEIP_SD_ENTRY_SUBSCRIBE_EVENTGROUP_ACK   = 0x07
} SomeIpSdEntryType;

// SOME/IP-SD Option Types
typedef enum SomeIpSdOptionType
{
   SOMEIP_SD_OPT_CONFIGURATION                = 0x01,
   SOMEIP_SD_OPT_LOAD_BALANCING               = 0x02,
   SOMEIP_SD_OPT_IPV4_ENDPOINT                = 0x04,
   SOMEIP_SD_OPT_IPV6_ENDPOINT                = 0x06,
   SOMEIP_SD_OPT_IPV4_MULTICAST               = 0x14,
   SOMEIP_SD_OPT_IPV4_SD_ENDPOINT             = 0x24
} SomeIpSdOptionType;

// SOME/IP-SD 16-byte Entry structure
typedef struct SomeIpSdEntry
{
   uint8_t type;
   uint8_t index1;
   uint8_t index2;
   uint8_t numOptions;
   uint16_t serviceId;
   uint16_t instanceId;
   uint8_t majorVersion;
   uint32_t ttl;            // 24 bits wire length
   uint32_t minorOrEventgroup; // 32 bits for Service, or eventgroupId (16 bits) + counter
} SomeIpSdEntry;

// SOME/IP-SD IPv4 Endpoint Option
typedef struct SomeIpSdOption
{
   uint8_t type;
   uint8_t ipv4[4];
   uint8_t protocol;        // 0x06 = TCP, 0x11 = UDP
   uint16_t port;
} SomeIpSdOption;

#define SOMEIP_SD_MAX_ENTRIES 8
#define SOMEIP_SD_MAX_OPTIONS 8

typedef struct SomeIpSdMessage
{
   uint8_t flags;           // Reboot flag (bit 7), Unicast flag (bit 6)
   uint32_t entryCount;
   SomeIpSdEntry entries[SOMEIP_SD_MAX_ENTRIES];
   uint32_t optionCount;
   SomeIpSdOption options[SOMEIP_SD_MAX_OPTIONS];
} SomeIpSdMessage;

// Service Discovery Registry Table
typedef struct SomeIpServiceOffer
{
   uint16_t serviceId;
   uint16_t instanceId;
   uint8_t majorVersion;
   uint32_t minorVersion;
   uint32_t ttl;
   uint8_t ipv4[4];
   uint16_t port;
   uint8_t protocol;
   bool active;
} SomeIpServiceOffer;

typedef struct SomeIpSubscription
{
   uint16_t serviceId;
   uint16_t instanceId;
   uint16_t eventgroupId;
   uint32_t ttl;
   uint8_t subscriberIpv4[4];
   uint16_t subscriberPort;
   bool active;
} SomeIpSubscription;

#define SOMEIP_MAX_OFFERS         16
#define SOMEIP_MAX_SUBSCRIPTIONS  16

typedef struct SomeIpSdEngine
{
   SomeIpServiceOffer offers[SOMEIP_MAX_OFFERS];
   uint32_t offerCount;
   SomeIpSubscription subscriptions[SOMEIP_MAX_SUBSCRIPTIONS];
   uint32_t subscriptionCount;
} SomeIpSdEngine;

// RPC Handler Callback
typedef bool (*SomeIpMethodHandler)(const SomeIpMessage* req, SomeIpMessage* resp);

typedef struct SomeIpMethodEntry
{
   uint16_t serviceId;
   uint16_t methodId;
   uint8_t interfaceVersion;
   SomeIpMethodHandler handler;
} SomeIpMethodEntry;

#define SOMEIP_MAX_RPC_METHODS 16

typedef struct SomeIpRouter
{
   SomeIpMethodEntry methods[SOMEIP_MAX_RPC_METHODS];
   uint32_t methodCount;
   uint16_t nextSessionId;
} SomeIpRouter;

// Function Prototypes

// Message and Header (SomeIpMessage.ec)
bool someip_header_encode(const SomeIpHeader* hdr, uint8_t* outBuf, uint32_t maxLen);
bool someip_header_decode(const uint8_t* inBuf, uint32_t inLen, SomeIpHeader* outHdr);
uint32_t someip_message_serialize(const SomeIpMessage* msg, uint8_t* outBuf, uint32_t maxLen);
bool someip_message_deserialize(const uint8_t* inBuf, uint32_t inLen, SomeIpMessage* outMsg);
void someip_message_init_response(const SomeIpMessage* req, SomeIpMessage* resp, uint8_t returnCode);

// Serializer (SomeIpSerializer.ec)
void someip_serializer_init(SomeIpSerializer* s, uint8_t* buf, uint32_t capacity);
bool someip_serialize_uint8(SomeIpSerializer* s, uint8_t val);
bool someip_serialize_uint16(SomeIpSerializer* s, uint16_t val);
bool someip_serialize_uint32(SomeIpSerializer* s, uint32_t val);
bool someip_serialize_uint64(SomeIpSerializer* s, uint64_t val);
bool someip_serialize_float32(SomeIpSerializer* s, float val);
bool someip_serialize_float64(SomeIpSerializer* s, double val);
bool someip_serialize_bytes(SomeIpSerializer* s, const uint8_t* data, uint32_t len);
bool someip_serialize_string(SomeIpSerializer* s, const char* str);

void someip_deserializer_init(SomeIpDeserializer* d, const uint8_t* buf, uint32_t length);
bool someip_deserialize_uint8(SomeIpDeserializer* d, uint8_t* outVal);
bool someip_deserialize_uint16(SomeIpDeserializer* d, uint16_t* outVal);
bool someip_deserialize_uint32(SomeIpDeserializer* d, uint32_t* outVal);
bool someip_deserialize_uint64(SomeIpDeserializer* d, uint64_t* outVal);
bool someip_deserialize_float32(SomeIpDeserializer* d, float* outVal);
bool someip_deserialize_float64(SomeIpDeserializer* d, double* outVal);
bool someip_deserialize_bytes(SomeIpDeserializer* d, uint8_t* outData, uint32_t len);
bool someip_deserialize_string(SomeIpDeserializer* d, char* outStr, uint32_t maxStrLen);

// SOME/IP-SD Parser (SomeIpSdParser.ec)
uint32_t someip_sd_serialize(const SomeIpSdMessage* sdMsg, uint8_t* outBuf, uint32_t maxLen);
bool someip_sd_deserialize(const uint8_t* inBuf, uint32_t inLen, SomeIpSdMessage* outSdMsg);

// SOME/IP-SD Engine (SomeIpSdEngine.ec)
void someip_sd_engine_init(SomeIpSdEngine* engine);
bool someip_sd_engine_offer_service(SomeIpSdEngine* engine, uint16_t serviceId, uint16_t instanceId, uint8_t majorVer, uint32_t minorVer, uint32_t ttl, const uint8_t* ipv4, uint16_t port, uint8_t protocol);
bool someip_sd_engine_stop_offer_service(SomeIpSdEngine* engine, uint16_t serviceId, uint16_t instanceId);
uint32_t someip_sd_engine_build_offers(const SomeIpSdEngine* engine, uint8_t* outBuf, uint32_t maxLen);
bool someip_sd_engine_process_sd_packet(SomeIpSdEngine* engine, const uint8_t* inBuf, uint32_t inLen, uint8_t* outResponse, uint32_t* outRespLen, uint32_t maxRespLen);

// RPC Dispatcher & Publisher (SomeIpRouter.ec)
void someip_router_init(SomeIpRouter* router);
bool someip_router_register_method(SomeIpRouter* router, uint16_t serviceId, uint16_t methodId, uint8_t interfaceVer, SomeIpMethodHandler handler);
bool someip_router_dispatch(SomeIpRouter* router, const SomeIpMessage* req, SomeIpMessage* resp);
uint32_t someip_router_publish_event(SomeIpRouter* router, uint16_t serviceId, uint16_t eventId, uint8_t interfaceVer, const uint8_t* data, uint32_t dataLen, uint8_t* outBuf, uint32_t maxLen);

#endif // MANIFOLD_SOMEIP_EH
