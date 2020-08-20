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
   XCP_CMD_DOWNLOAD                    = 0xF0,
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
   uint8_t bitOffset;
} XcpOdtEntry;

#define XCP_MAX_ODT_PER_DAQ            16
#define XCP_MAX_ENTRIES_PER_ODT        8
#define XCP_MAX_DAQ_LISTS              8
#define XCP_CAL_PAGE_SIZE              4096

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

typedef struct XcpServer
{
   bool isConnected;
   uint32_t currentMta;
   uint8_t mtaExtension;

   // Calibration pages: Segment 0 holds Flash (page 0) and RAM (page 1)
   uint8_t flashCalPage[XCP_CAL_PAGE_SIZE];
   uint8_t ramCalPage[XCP_CAL_PAGE_SIZE];
   uint8_t ecuCalPage; // Currently executing page (0: Flash, 1: RAM)
   uint8_t xcpCalPage; // Currently accessed page by XCP (0: Flash, 1: RAM)

   // DAQ lists
   XcpDaqList daqLists[XCP_MAX_DAQ_LISTS];
   uint8_t daqCount;
   bool daqRunning;

   // DAQ pointer state for SET_DAQ_PTR / WRITE_DAQ
   uint16_t curDaqList;
   uint8_t curOdt;
   uint8_t curOdtEntry;
} XcpServer;

// Function Prototypes

// Server and Command Processing (XcpProtocol.ec)
void xcp_server_init(XcpServer* server);
uint32_t xcp_process_command(XcpServer* server, const uint8_t* cmd, uint32_t cmdLen, uint8_t* resp, uint32_t maxRespLen);
uint32_t xcp_build_error_response(uint8_t errCode, uint8_t* resp, uint32_t maxRespLen);

// Memory Access and Transfer (XcpMemory.ec)
bool xcp_set_mta(XcpServer* server, uint32_t address, uint8_t extension);
uint32_t xcp_upload(XcpServer* server, uint8_t numBytes, uint8_t* resp, uint32_t maxRespLen);
uint32_t xcp_short_upload(XcpServer* server, uint32_t address, uint8_t extension, uint8_t numBytes, uint8_t* resp, uint32_t maxRespLen);
bool xcp_download(XcpServer* server, const uint8_t* data, uint8_t numBytes);

// DAQ Allocation and Configuration (XcpDaqAlloc.ec)
bool xcp_alloc_daq(XcpServer* server, uint16_t daqCount);
bool xcp_alloc_odt(XcpServer* server, uint16_t daqList, uint8_t odtCount);
bool xcp_alloc_odt_entry(XcpServer* server, uint16_t daqList, uint8_t odt, uint8_t odtEntries);
bool xcp_set_daq_ptr(XcpServer* server, uint16_t daqList, uint8_t odt, uint8_t odtEntry);
bool xcp_write_daq(XcpServer* server, uint8_t bitOffset, uint8_t size, uint8_t ext, uint32_t address);
bool xcp_set_daq_list_mode(XcpServer* server, uint16_t daqList, uint8_t mode, uint16_t eventChannel, uint8_t prescaler, uint8_t priority);
bool xcp_start_stop_daq_list(XcpServer* server, uint8_t mode, uint16_t daqList);
bool xcp_start_stop_synch(XcpServer* server, uint8_t mode);

// DAQ Streaming Engine (XcpDaqStream.ec)
uint32_t xcp_sample_daq_event(XcpServer* server, uint16_t eventChannel, uint32_t timestampUs, uint8_t* outDtoBuffer, uint32_t maxLen, uint32_t* dtoOffsets, uint32_t maxDtos);

// Calibration Page Switching and Checksumming (XcpCalPage.ec)
bool xcp_set_cal_page(XcpServer* server, uint8_t segment, uint8_t page, uint8_t mode);
uint8_t xcp_get_cal_page(const XcpServer* server, uint8_t segment, uint8_t mode);
bool xcp_copy_cal_page(XcpServer* server, uint8_t srcSeg, uint8_t srcPage, uint8_t dstSeg, uint8_t dstPage);
uint32_t xcp_build_checksum(XcpServer* server, uint32_t blockSize, uint8_t* resp, uint32_t maxRespLen);

#endif // MANIFOLD_XCP_EH
