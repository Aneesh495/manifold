// include/uds.eh
// ISO 14229-1 Unified Diagnostic Services (UDS) service IDs, DIDs, and server engine.

#ifndef MANIFOLD_UDS_EH
#define MANIFOLD_UDS_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

// Standard Service Identifiers (SID)
typedef enum UdsServiceId
{
   UDS_SID_DIAGNOSTIC_SESSION_CONTROL       = 0x10,
   UDS_SID_ECU_RESET                        = 0x11,
   UDS_SID_CLEAR_DIAGNOSTIC_INFORMATION     = 0x14,
   UDS_SID_READ_DTC_INFORMATION             = 0x19,
   UDS_SID_READ_DATA_BY_IDENTIFIER          = 0x22,
   UDS_SID_SECURITY_ACCESS                  = 0x27,
   UDS_SID_COMMUNICATION_CONTROL            = 0x28,
   UDS_SID_WRITE_DATA_BY_IDENTIFIER         = 0x2E,
   UDS_SID_INPUT_OUTPUT_CONTROL_BY_ID       = 0x2F,
   UDS_SID_ROUTINE_CONTROL                  = 0x31,
   UDS_SID_REQUEST_DOWNLOAD                 = 0x34,
   UDS_SID_TRANSFER_DATA                    = 0x36,
   UDS_SID_REQUEST_TRANSFER_EXIT            = 0x37,
   UDS_SID_TESTER_PRESENT                   = 0x3E,
   UDS_SID_NEGATIVE_RESPONSE                = 0x7F
} UdsServiceId;

// Well-known Diagnostic Data Identifiers (DID)
#define UDS_DID_VIN_NUMBER                  0xF190
#define UDS_DID_ECU_SERIAL_NUMBER           0xF18C
#define UDS_DID_BOOT_SOFTWARE_ID            0xF180
#define UDS_DID_APPLICATION_SOFTWARE_ID     0xF189
#define UDS_DID_VEHICLE_SPEED               0x0100
#define UDS_DID_ENGINE_RPM                  0x0101
#define UDS_DID_BATTERY_VOLTAGE             0x0102
#define UDS_DID_COOLANT_TEMPERATURE         0x0103
#define UDS_DID_ODOMETER                    0x0104

// Maximum UDS diagnostic message payload length
#define UDS_MAX_PAYLOAD_SIZE 4096

// Security Access state
typedef struct UdsSecurityContext
{
   uint8_t currentLevel;      // 0: Locked, 1: Level 1 Unlocked, 3: Level 3 Unlocked, etc.
   uint32_t activeSeed;       // Active cryptographic challenge seed
   bool seedGenerated;
   uint8_t failedAttempts;
   uint64_t lockoutUntilMs;
} UdsSecurityContext;

// UDS Server context
typedef struct UdsServer
{
   DiagnosticSessionType currentSession;
   UdsSecurityContext security;
   bool communicationEnabled;
   uint64_t lastTesterPresentMs;
   uint32_t activeTransferAddress;
   uint32_t activeTransferSize;
   uint32_t transferredBytes;
   uint8_t nextBlockSequence;
   bool transferActive;
} UdsServer;

void uds_server_init(UdsServer* server);
void uds_server_process_request(UdsServer* server, const uint8_t* req, uint32_t reqLen,
                                uint8_t* resp, uint32_t* respLen);

typedef struct UdsDidDefinition
{
   uint16_t did;
   const char* name;
   uint16_t length;
   bool isWritable;
   uint8_t readSecurityLevel;
   uint8_t writeSecurityLevel;
   const char* defaultPayload;
} UdsDidDefinition;

const UdsDidDefinition* uds_did_catalog_lookup(uint16_t did);
bool uds_did_catalog_read(uint16_t did, uint8_t* outBuf, uint32_t* outLen, uint32_t maxLen);

#endif // MANIFOLD_UDS_EH
