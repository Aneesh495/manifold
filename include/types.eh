// include/types.eh
// Core type definitions, bitclasses, and byte order primitives for manifold.
// Standard C11 / eC compatibility header.

#ifndef MANIFOLD_TYPES_EH
#define MANIFOLD_TYPES_EH

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Common return status for all manifold operations
typedef enum ManifoldStatus
{
   MANIFOLD_OK = 0,
   MANIFOLD_ERR_INVALID_PARAM = 1,
   MANIFOLD_ERR_BUFFER_OVERFLOW = 2,
   MANIFOLD_ERR_TIMEOUT = 3,
   MANIFOLD_ERR_SECURITY_DENIED = 4,
   MANIFOLD_ERR_NOT_FOUND = 5,
   MANIFOLD_ERR_BUS_OFF = 6,
   MANIFOLD_ERR_CRC_MISMATCH = 7,
   MANIFOLD_ERR_SEQUENCE = 8,
   MANIFOLD_ERR_UNSUPPORTED = 9
} ManifoldStatus;

// Endianness for in-vehicle signals and network serializations
typedef enum Endianness
{
   ENDIAN_INTEL = 0,    // Little Endian (least significant byte first)
   ENDIAN_MOTOROLA = 1  // Big Endian (most significant byte first)
} Endianness;

// Monotonic timestamp structure with microsecond resolution
typedef struct Timestamp
{
   uint64_t seconds;
   uint32_t microseconds;
} Timestamp;

// Bitclass representing CAN arbitration flags
typedef struct CanIdFlags
{
   unsigned int isExtended : 1;
   unsigned int isRemote : 1;
   unsigned int isFd : 1;
   unsigned int bitRateSwitch : 1;
   unsigned int errorState : 1;
   unsigned int reserved : 27;
} CanIdFlags;

// Diagnostic session modes matching ISO 14229-1 specification
typedef enum DiagnosticSessionType
{
   DIAG_SESSION_DEFAULT = 0x01,
   DIAG_SESSION_PROGRAMMING = 0x02,
   DIAG_SESSION_EXTENDED = 0x03,
   DIAG_SESSION_SAFETY_SYSTEM = 0x04
} DiagnosticSessionType;

// ISO 14229 Negative Response Codes (NRC)
typedef enum NegativeResponseCode
{
   NRC_POSITIVE_RESPONSE = 0x00,
   NRC_GENERAL_REJECT = 0x10,
   NRC_SERVICE_NOT_SUPPORTED = 0x11,
   NRC_SUBFUNCTION_NOT_SUPPORTED = 0x12,
   NRC_INCORRECT_MESSAGE_LENGTH_OR_FORMAT = 0x13,
   NRC_RESPONSE_TOO_LONG = 0x14,
   NRC_BUSY_REPEAT_REQUEST = 0x21,
   NRC_CONDITIONS_NOT_CORRECT = 0x22,
   NRC_REQUEST_SEQUENCE_ERROR = 0x24,
   NRC_NO_RESPONSE_FROM_SUBNET_COMPONENT = 0x25,
   NRC_FAILURE_PREVENTS_EXECUTION_OF_REQUESTED_ACTION = 0x26,
   NRC_REQUEST_OUT_OF_RANGE = 0x31,
   NRC_SECURITY_ACCESS_DENIED = 0x33,
   NRC_INVALID_KEY = 0x35,
   NRC_EXCEEDED_NUMBER_OF_ATTEMPTS = 0x36,
   NRC_REQUIRED_TIME_DELAY_NOT_EXPIRED = 0x37,
   NRC_UPLOAD_DOWNLOAD_NOT_ACCEPTED = 0x70,
   NRC_TRANSFER_DATA_SUSPENDED = 0x71,
   NRC_GENERAL_PROGRAMMING_FAILURE = 0x72,
   NRC_WRONG_BLOCK_SEQUENCE_COUNTER = 0x73,
   NRC_REQUEST_CORRECTLY_RECEIVED_RESPONSE_PENDING = 0x78,
   NRC_SUBFUNCTION_NOT_SUPPORTED_IN_ACTIVE_SESSION = 0x7E,
   NRC_SERVICE_NOT_SUPPORTED_IN_ACTIVE_SESSION = 0x7F
} NegativeResponseCode;

// DTC Status Mask bits as defined in ISO 14229-1 Table D.1
typedef struct DtcStatusMask
{
   unsigned int testFailed : 1;
   unsigned int testFailedThisOperationCycle : 1;
   unsigned int pendingDtc : 1;
   unsigned int confirmedDtc : 1;
   unsigned int testNotCompletedSinceLastClear : 1;
   unsigned int testFailedSinceLastClear : 1;
   unsigned int testNotCompletedThisOperationCycle : 1;
   unsigned int warningIndicatorRequested : 1;
} DtcStatusMask;

// High-precision physical value container for signal conversions
typedef struct PhysicalValue
{
   double rawValue;
   double physicalValue;
   bool isValid;
   Timestamp captureTime;
} PhysicalValue;

#endif // MANIFOLD_TYPES_EH
