// include/xcp.eh
// ASAM Universal Measurement and Calibration Protocol (XCP) definitions.

#ifndef MANIFOLD_XCP_EH
#define MANIFOLD_XCP_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

// XCP Standard Commands
typedef enum XcpCommandCode
{
   XCP_CMD_CONNECT                     = 0xFF,
   XCP_CMD_DISCONNECT                  = 0xFE,
   XCP_CMD_GET_STATUS                  = 0xFD,
   XCP_CMD_SYNCH                       = 0xFC,
   XCP_CMD_GET_COMM_MODE_INFO          = 0xFB,
   XCP_CMD_GET_ID                      = 0xFA,
   XCP_CMD_SET_MTA                     = 0xF6,
   XCP_CMD_UPLOAD                      = 0xF5,
   XCP_CMD_SHORT_UPLOAD                = 0xF4,
   XCP_CMD_BUILD_CHECKSUM              = 0xF3,
   XCP_CMD_SET_CAL_PAGE                = 0xEB,
   XCP_CMD_GET_CAL_PAGE                = 0xEA,
   XCP_CMD_COPY_CAL_PAGE               = 0xE4,
   XCP_CMD_CLEAR_DAQ_LIST              = 0xE3,
   XCP_CMD_SET_DAQ_PTR                 = 0xE2,
   XCP_CMD_WRITE_DAQ                   = 0xE1,
   XCP_CMD_SET_DAQ_LIST_MODE           = 0xE0,
   XCP_CMD_START_STOP_DAQ_LIST         = 0xDE,
   XCP_CMD_START_STOP_SYNCH            = 0xDD,
   XCP_CMD_ALLOC_DAQ                   = 0xD7,
   XCP_CMD_ALLOC_ODT                   = 0xD6,
   XCP_CMD_ALLOC_ODT_ENTRY             = 0xD5,
   XCP_CMD_PROGRAM_START               = 0xD2,
   XCP_CMD_PROGRAM_CLEAR               = 0xD1,
   XCP_CMD_PROGRAM                     = 0xD0,
   XCP_CMD_PROGRAM_RESET               = 0xCF
} XcpCommandCode;

// XCP Packet Identifiers (PID)
#define XCP_PID_CMD_RESPONSE           0xFF
#define XCP_PID_ERROR_RESPONSE         0xFE
#define XCP_PID_EVENT_PACKET           0xFD
#define XCP_PID_SERVICE_PACKET         0xFC

// XCP Error Codes
typedef enum XcpErrorCode
{
   XCP_ERR_CMD_SYNCH                   = 0x00,
   XCP_ERR_CMD_BUSY                    = 0x10,
   XCP_ERR_DAQ_ACTIVE                  = 0x11,
   XCP_ERR_PGM_ACTIVE                  = 0x12,
   XCP_ERR_CMD_UNKNOWN                 = 0x20,
   XCP_ERR_CMD_SYNTAX                  = 0x21,
   XCP_ERR_OUT_OF_RANGE                = 0x22,
   XCP_ERR_WRITE_PROTECTED             = 0x23,
   XCP_ERR_ACCESS_DENIED               = 0x24,
   XCP_ERR_ACCESS_LOCKED               = 0x25,
   XCP_ERR_PAGE_NOT_VALID              = 0x26,
   XCP_ERR_PAGE_MODE_NOT_VALID         = 0x27,
   XCP_ERR_SEGMENT_NOT_VALID           = 0x28,
   XCP_ERR_SEQUENCE                    = 0x29,
   XCP_ERR_DAQ_CONFIG                  = 0x2A,
   XCP_ERR_MEMORY_OVERFLOW             = 0x30,
   XCP_ERR_GENERIC                     = 0x31,
   XCP_ERR_VERIFY                      = 0x32
} XcpErrorCode;

// ODT Entry definition
typedef struct XcpOdtEntry
{
   uint32_t address;
   uint8_t length;
   uint8_t extension;
} XcpOdtEntry;

#define XCP_MAX_ODT_PER_DAQ 16
#define XCP_MAX_ENTRIES_PER_ODT 8

typedef struct XcpOdt
{
   XcpOdtEntry entries[XCP_MAX_ENTRIES_PER_ODT];
   uint8_t entryCount;
} XcpOdt;

typedef struct XcpDaqList
{
   XcpOdt odts[XCP_MAX_ODT_PER_DAQ];
   uint8_t odtCount;
   uint8_t mode;             // Bit 0: Alternate, Bit 1: Direction (0=DAQ, 1=STIM), Bit 2: Timestamp
   uint16_t eventChannel;
   uint8_t prescaler;
   uint8_t priority;
   bool isRunning;
} XcpDaqList;

#define XCP_MAX_DAQ_LISTS 8

typedef struct XcpServer
{
   bool isConnected;
   uint32_t currentMta;
   uint8_t activeCalPage;
   XcpDaqList daqLists[XCP_MAX_DAQ_LISTS];
   uint8_t daqCount;
} XcpServer;

#endif // MANIFOLD_XCP_EH
