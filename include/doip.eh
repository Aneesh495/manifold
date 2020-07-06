// include/doip.eh
// ISO 13400-2 Diagnostic over IP (DoIP) message definitions and session manager.

#ifndef MANIFOLD_DOIP_EH
#define MANIFOLD_DOIP_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define DOIP_PROTOCOL_VERSION 0x02
#define DOIP_INVERSE_VERSION  0xFD
#define DOIP_HEADER_SIZE      8

#define DOIP_DEFAULT_TCP_PORT 13400
#define DOIP_DEFAULT_UDP_PORT 13400

#define DOIP_MAX_SESSIONS     8
#define DOIP_MAX_PAYLOAD_SIZE 65536

// DoIP Generic Header NACK Codes (ISO 13400-2 Table 10)
typedef enum DoipGenericNackCode
{
   DOIP_NACK_INCORRECT_PATTERN_FORMAT   = 0x00,
   DOIP_NACK_UNKNOWN_PAYLOAD_TYPE       = 0x01,
   DOIP_NACK_MESSAGE_TOO_LARGE          = 0x02,
   DOIP_NACK_OUT_OF_MEMORY              = 0x03,
   DOIP_NACK_INVALID_PAYLOAD_LENGTH     = 0x04
} DoipGenericNackCode;

// DoIP Payload Types (ISO 13400-2 Table 16)
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
   DOIP_TYPE_DIAGNOSTIC_POWER_MODE_REQUEST       = 0x4003,
   DOIP_TYPE_DIAGNOSTIC_POWER_MODE_RESPONSE      = 0x4004,
   DOIP_TYPE_DIAGNOSTIC_MESSAGE                  = 0x8001,
   DOIP_TYPE_DIAGNOSTIC_POSITIVE_ACK             = 0x8002,
   DOIP_TYPE_DIAGNOSTIC_NEGATIVE_ACK             = 0x8003
} DoipPayloadType;

// Routing Activation Response Codes (ISO 13400-2 Table 20)
typedef enum DoipRoutingActivationResponse
{
   DOIP_ROUTING_ERR_UNKNOWN_SA                   = 0x00,
   DOIP_ROUTING_ERR_ALL_SOCKETS_REGISTERED       = 0x01,
   DOIP_ROUTING_ERR_SA_DIFFERENT                 = 0x02,
   DOIP_ROUTING_ERR_SA_ALREADY_REGISTERED        = 0x03,
   DOIP_ROUTING_ERR_MISSING_AUTHENTICATION       = 0x04,
   DOIP_ROUTING_ERR_REJECTED_CONFIRMATION        = 0x05,
   DOIP_ROUTING_ERR_UNSUPPORTED_TYPE             = 0x06,
   DOIP_ROUTING_SUCCESS                          = 0x10,
   DOIP_ROUTING_SUCCESS_CONFIRMATION_REQUIRED    = 0x11
} DoipRoutingActivationResponse;

// Diagnostic Message Negative ACK Codes (ISO 13400-2 Table 26)
typedef enum DoipDiagNackCode
{
   DOIP_DIAG_NACK_INVALID_SOURCE_ADDRESS         = 0x02,
   DOIP_DIAG_NACK_UNKNOWN_TARGET_ADDRESS         = 0x03,
   DOIP_DIAG_NACK_MESSAGE_TOO_LARGE              = 0x04,
   DOIP_DIAG_NACK_OUT_OF_MEMORY                  = 0x05,
   DOIP_DIAG_NACK_TARGET_UNREACHABLE             = 0x06,
   DOIP_DIAG_NACK_UNKNOWN_NETWORK                = 0x07,
   DOIP_DIAG_NACK_TRANSPORT_ERROR                = 0x08
} DoipDiagNackCode;

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
   uint32_t connectionId;
   uint16_t clientLogicalAddress;
   bool isActivated;
   uint8_t activationType;
   uint64_t lastActivityMs;
   bool aliveCheckPending;
} DoipSession;

// DoIP Entity / Gateway Node
typedef struct DoipNode
{
   char vin[17];
   uint16_t logicalAddress;
   uint8_t eid[6];
   uint8_t gid[6];
   uint8_t furtherAction;
   uint8_t syncStatus;
   uint32_t maxPayloadLength;
   uint64_t aliveCheckTimeoutMs;
   DoipSession sessions[DOIP_MAX_SESSIONS];
   uint32_t activeSessionCount;
} DoipNode;

// Function prototypes

// Header serialization and parsing (DoipHeader.ec)
bool doip_header_encode(const DoipHeader* hdr, uint8_t* outBuf, uint32_t maxLen);
bool doip_header_decode(const uint8_t* inBuf, uint32_t inLen, DoipHeader* outHdr, uint8_t* nackCode);
uint32_t doip_build_generic_nack(uint8_t nackCode, uint8_t* outBuf, uint32_t maxLen);

// Node initialization
void doip_node_init(DoipNode* node, const char* vin, uint16_t logicalAddress, const uint8_t* eid, const uint8_t* gid);

// Discovery and Identification (DoipDiscovery.ec)
uint32_t doip_build_vehicle_announcement(const DoipNode* node, uint8_t* outBuf, uint32_t maxLen);
uint32_t doip_handle_vehicle_ident_request(const DoipNode* node, const uint8_t* inBuf, uint32_t inLen, uint8_t* outBuf, uint32_t maxLen);

// Routing Activation (DoipActivation.ec)
uint32_t doip_process_routing_activation(DoipNode* node, uint32_t connId, const uint8_t* payload, uint32_t payloadLen, uint8_t* outBuf, uint32_t maxLen);
DoipSession* doip_find_session(DoipNode* node, uint32_t connId);
bool doip_close_session(DoipNode* node, uint32_t connId);

// Alive Check Supervision (DoipAliveCheck.ec)
uint32_t doip_build_alive_check_request(uint8_t* outBuf, uint32_t maxLen);
bool doip_process_alive_check_response(DoipNode* node, uint32_t connId, const uint8_t* payload, uint32_t payloadLen);
void doip_check_alive_timeouts(DoipNode* node, uint64_t currentMs, void (*onTimeout)(uint32_t connId));

// Diagnostic Message Encapsulation and Routing (DoipRouter.ec)
typedef void (*DoipUdsHandler)(uint16_t sa, uint16_t ta, const uint8_t* udsReq, uint32_t udsLen, uint8_t* udsResp, uint32_t* udsRespLen, uint32_t maxRespLen);

uint32_t doip_process_diagnostic_message(DoipNode* node, uint32_t connId, const uint8_t* payload, uint32_t payloadLen, uint8_t* outBuf, uint32_t maxLen, DoipUdsHandler udsCallback);
uint32_t doip_build_diagnostic_ack(uint16_t sourceAddr, uint16_t targetAddr, uint8_t ackCode, const uint8_t* prevData, uint32_t prevDataLen, uint8_t* outBuf, uint32_t maxLen);
uint32_t doip_build_diagnostic_nack(uint16_t sourceAddr, uint16_t targetAddr, uint8_t nackCode, const uint8_t* prevData, uint32_t prevDataLen, uint8_t* outBuf, uint32_t maxLen);

#endif // MANIFOLD_DOIP_EH
