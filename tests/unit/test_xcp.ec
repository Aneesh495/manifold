// tests/unit/test_xcp.ec
// Unit tests for ASAM XCP Command Processor, Memory Access, Calibration Pages, and DAQ Streaming.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#include "types.eh"
#include "xcp.eh"
#include "ec_runtime.h"

// Forward declarations
bool test_xcp_connect_status_and_id(void);
bool test_xcp_memory_upload_download_and_checksum(void);
bool test_xcp_cal_page_switching_and_copy(void);
bool test_xcp_dynamic_daq_allocation_and_streaming(void);

bool test_xcp_connect_status_and_id(void)
{
   XcpServer server;
   xcp_server_init(&server);

   uint8_t resp[128];

   // 1. Pre-connect commands must be rejected
   uint8_t getStatusCmd[1] = { XCP_CMD_GET_STATUS };
   uint32_t respLen = xcp_process_command(&server, getStatusCmd, 1, resp, sizeof(resp));
   assert(respLen == 2);
   assert(resp[0] == XCP_PID_ERROR_RESPONSE && resp[1] == XCP_ERR_CMD_UNKNOWN);

   // 2. SYNCH before CONNECT must return XCP_ERR_CMD_SYNCH
   uint8_t synchCmd[1] = { XCP_CMD_SYNCH };
   respLen = xcp_process_command(&server, synchCmd, 1, resp, sizeof(resp));
   assert(respLen == 2);
   assert(resp[0] == XCP_PID_ERROR_RESPONSE && resp[1] == XCP_ERR_CMD_SYNCH);

   // 3. CONNECT command
   uint8_t connectCmd[2] = { XCP_CMD_CONNECT, 0x00 };
   respLen = xcp_process_command(&server, connectCmd, 2, resp, sizeof(resp));
   assert(respLen == 8);
   assert(resp[0] == XCP_PID_CMD_RESPONSE);
   assert(resp[1] == 0x15); // Resources: CAL/PAG, DAQ, PGM
   assert(server.isConnected);

   // 4. GET_STATUS
   respLen = xcp_process_command(&server, getStatusCmd, 1, resp, sizeof(resp));
   assert(respLen == 6);
   assert(resp[0] == XCP_PID_CMD_RESPONSE);

   // 5. GET_ID
   uint8_t getIdCmd[2] = { XCP_CMD_GET_ID, 0x00 };
   respLen = xcp_process_command(&server, getIdCmd, 2, resp, sizeof(resp));
   assert(respLen >= 8);
   assert(resp[0] == XCP_PID_CMD_RESPONSE);
   assert(memcmp(resp + 8, "MANIFOLD_IVN_XCP_GATEWAY", 24) == 0);

   // 6. DISCONNECT
   uint8_t disconnCmd[1] = { XCP_CMD_DISCONNECT };
   respLen = xcp_process_command(&server, disconnCmd, 1, resp, sizeof(resp));
   assert(respLen == 1 && resp[0] == XCP_PID_CMD_RESPONSE);
   assert(!server.isConnected);

   return true;
}

bool test_xcp_memory_upload_download_and_checksum(void)
{
   XcpServer server;
   xcp_server_init(&server);

   uint8_t connectCmd[2] = { XCP_CMD_CONNECT, 0x00 };
   uint8_t resp[128];
   xcp_process_command(&server, connectCmd, 2, resp, sizeof(resp));

   // 1. SET_MTA to RAM page (Ext 0), address 0x0100
   uint8_t setMtaCmd[8] = { XCP_CMD_SET_MTA, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00 };
   uint32_t respLen = xcp_process_command(&server, setMtaCmd, 8, resp, sizeof(resp));
   assert(respLen == 1 && resp[0] == XCP_PID_CMD_RESPONSE);

   // 2. DOWNLOAD 4 bytes: 0x11, 0x22, 0x33, 0x44
   uint8_t downloadCmd[6] = { XCP_CMD_DOWNLOAD, 4, 0x11, 0x22, 0x33, 0x44 };
   respLen = xcp_process_command(&server, downloadCmd, 6, resp, sizeof(resp));
   assert(respLen == 1 && resp[0] == XCP_PID_CMD_RESPONSE);

   // 3. Reset MTA and UPLOAD 4 bytes
   xcp_process_command(&server, setMtaCmd, 8, resp, sizeof(resp));
   uint8_t uploadCmd[2] = { XCP_CMD_UPLOAD, 4 };
   respLen = xcp_process_command(&server, uploadCmd, 2, resp, sizeof(resp));
   assert(respLen == 5); // PID + 4 bytes
   assert(resp[0] == XCP_PID_CMD_RESPONSE);
   assert(resp[1] == 0x11 && resp[2] == 0x22 && resp[3] == 0x33 && resp[4] == 0x44);

   // 4. SHORT_UPLOAD 4 bytes from address 0x0100
   uint8_t shortUpCmd[8] = { XCP_CMD_SHORT_UPLOAD, 4, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00 };
   respLen = xcp_process_command(&server, shortUpCmd, 8, resp, sizeof(resp));
   assert(respLen == 5);
   assert(resp[1] == 0x11 && resp[2] == 0x22 && resp[3] == 0x33 && resp[4] == 0x44);

   // 5. BUILD_CHECKSUM over the 4 downloaded bytes: sum = 0x11+0x22+0x33+0x44 = 0xAA
   xcp_process_command(&server, setMtaCmd, 8, resp, sizeof(resp));
   uint8_t chkCmd[8] = { XCP_CMD_BUILD_CHECKSUM, 0, 0, 0, 4, 0, 0, 0 };
   respLen = xcp_process_command(&server, chkCmd, 8, resp, sizeof(resp));
   assert(respLen == 8);
   assert(resp[0] == XCP_PID_CMD_RESPONSE);
   assert(resp[4] == 0xAA && resp[5] == 0x00 && resp[6] == 0x00 && resp[7] == 0x00);

   // 6. Switch XCP access to Flash reference page (page 0) and attempt DOWNLOAD
   uint8_t setPageCmd[4] = { XCP_CMD_SET_CAL_PAGE, 0x02, 0x00, 0x00 }; // Mode 0x02 (XCP), Seg 0, Page 0
   xcp_process_command(&server, setPageCmd, 4, resp, sizeof(resp));
   xcp_process_command(&server, setMtaCmd, 8, resp, sizeof(resp));

   respLen = xcp_process_command(&server, downloadCmd, 6, resp, sizeof(resp));
   assert(respLen == 2);
   assert(resp[0] == XCP_PID_ERROR_RESPONSE && resp[1] == XCP_ERR_ACCESS_DENIED);

   return true;
}

bool test_xcp_cal_page_switching_and_copy(void)
{
   XcpServer server;
   xcp_server_init(&server);

   uint8_t connectCmd[2] = { XCP_CMD_CONNECT, 0x00 };
   uint8_t resp[64];
   xcp_process_command(&server, connectCmd, 2, resp, sizeof(resp));

   // 1. Verify default ECU page is 0 (Flash), XCP page is 1 (RAM)
   uint8_t getPageEcu[3] = { XCP_CMD_GET_CAL_PAGE, 0x01, 0x00 };
   uint32_t respLen = xcp_process_command(&server, getPageEcu, 3, resp, sizeof(resp));
   assert(respLen == 4 && resp[3] == 0);

   uint8_t getPageXcp[3] = { XCP_CMD_GET_CAL_PAGE, 0x02, 0x00 };
   respLen = xcp_process_command(&server, getPageXcp, 3, resp, sizeof(resp));
   assert(respLen == 4 && resp[3] == 1);

   // 2. Switch ECU execution page to working page 1
   uint8_t setPageEcu[4] = { XCP_CMD_SET_CAL_PAGE, 0x01, 0x00, 0x01 };
   respLen = xcp_process_command(&server, setPageEcu, 4, resp, sizeof(resp));
   assert(respLen == 1 && resp[0] == XCP_PID_CMD_RESPONSE);

   respLen = xcp_process_command(&server, getPageEcu, 3, resp, sizeof(resp));
   assert(respLen == 4 && resp[3] == 1);

   // 3. Mutate RAM calibration page at offset 0x0050
   server.ramCalPage[0x0050] = 0xAA;
   assert(server.ramCalPage[0x0050] != server.flashCalPage[0x0050]);

   // 4. COPY_CAL_PAGE from Flash (0) to RAM (1) to restore baseline calibration
   uint8_t copyCmd[5] = { XCP_CMD_COPY_CAL_PAGE, 0x00, 0x00, 0x00, 0x01 };
   respLen = xcp_process_command(&server, copyCmd, 5, resp, sizeof(resp));
   assert(respLen == 1 && resp[0] == XCP_PID_CMD_RESPONSE);
   assert(server.ramCalPage[0x0050] == server.flashCalPage[0x0050]);

   // 5. Attempt copy targeting Flash page 0 (must be rejected)
   uint8_t copyToFlash[5] = { XCP_CMD_COPY_CAL_PAGE, 0x00, 0x01, 0x00, 0x00 };
   respLen = xcp_process_command(&server, copyToFlash, 5, resp, sizeof(resp));
   assert(respLen == 2 && resp[0] == XCP_PID_ERROR_RESPONSE);

   return true;
}

bool test_xcp_dynamic_daq_allocation_and_streaming(void)
{
   XcpServer server;
   xcp_server_init(&server);

   uint8_t connectCmd[2] = { XCP_CMD_CONNECT, 0x00 };
   uint8_t resp[64];
   xcp_process_command(&server, connectCmd, 2, resp, sizeof(resp));

   // 1. ALLOC_DAQ: 1 list
   uint8_t allocDaqCmd[4] = { XCP_CMD_ALLOC_DAQ, 0x00, 0x01, 0x00 };
   assert(xcp_process_command(&server, allocDaqCmd, 4, resp, sizeof(resp)) == 1);

   // 2. ALLOC_ODT on DAQ 0: 1 ODT
   uint8_t allocOdtCmd[4] = { XCP_CMD_ALLOC_ODT, 0x01, 0x00, 0x00 };
   assert(xcp_process_command(&server, allocOdtCmd, 4, resp, sizeof(resp)) == 1);

   // 3. ALLOC_ODT_ENTRY on DAQ 0, ODT 0: 2 entries
   uint8_t allocEntryCmd[5] = { XCP_CMD_ALLOC_ODT_ENTRY, 0x02, 0x00, 0x00, 0x00 };
   assert(xcp_process_command(&server, allocEntryCmd, 5, resp, sizeof(resp)) == 1);

   // 4. SET_DAQ_PTR to DAQ 0, ODT 0, Entry 0
   uint8_t setPtrCmd[6] = { XCP_CMD_SET_DAQ_PTR, 0x00, 0x00, 0x00, 0x00, 0x00 };
   assert(xcp_process_command(&server, setPtrCmd, 6, resp, sizeof(resp)) == 1);

   // 5. WRITE_DAQ Entry 0: addr 0x0010, size 2 (auto-increments pointer to Entry 1)
   uint8_t writeDaq0[8] = { XCP_CMD_WRITE_DAQ, 0x00, 0x02, 0x00, 0x10, 0x00, 0x00, 0x00 };
   assert(xcp_process_command(&server, writeDaq0, 8, resp, sizeof(resp)) == 1);

   // 6. WRITE_DAQ Entry 1: addr 0x0020, size 4
   uint8_t writeDaq1[8] = { XCP_CMD_WRITE_DAQ, 0x00, 0x04, 0x00, 0x20, 0x00, 0x00, 0x00 };
   assert(xcp_process_command(&server, writeDaq1, 8, resp, sizeof(resp)) == 1);

   // 7. SET_DAQ_LIST_MODE: DAQ 0, mode 0x04 (Timestamp), eventChannel 1, prescaler 1
   uint8_t setModeCmd[8] = { XCP_CMD_SET_DAQ_LIST_MODE, 0x04, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00 };
   assert(xcp_process_command(&server, setModeCmd, 8, resp, sizeof(resp)) == 1);

   // 8. START_STOP_DAQ_LIST: Start DAQ 0
   uint8_t startDaqCmd[4] = { XCP_CMD_START_STOP_DAQ_LIST, 0x01, 0x00, 0x00 };
   assert(xcp_process_command(&server, startDaqCmd, 4, resp, sizeof(resp)) == 2);

   // Setup mock memory values at 0x0010 and 0x0020
   server.ramCalPage[0x0010] = 0xAA;
   server.ramCalPage[0x0011] = 0xBB;
   server.ramCalPage[0x0020] = 0x12;
   server.ramCalPage[0x0021] = 0x34;
   server.ramCalPage[0x0022] = 0x56;
   server.ramCalPage[0x0023] = 0x78;

   // 9. Sample DAQ event for eventChannel 1 with timestamp 0x01020304
   uint8_t dtoBuffer[128];
   uint32_t dtoOffsets[8];
   uint32_t totalBytes = xcp_sample_daq_event(&server, 1, 0x01020304, dtoBuffer, sizeof(dtoBuffer), dtoOffsets, 8);

   // DTO length: 1 byte PID + 4 bytes timestamp + 2 bytes entry0 + 4 bytes entry1 = 11 bytes
   assert(totalBytes == 11);
   assert(dtoOffsets[0] == 0);
   assert(dtoBuffer[0] == 0x00); // PID 0
   // Timestamp (little endian 0x01020304)
   assert(dtoBuffer[1] == 0x04 && dtoBuffer[2] == 0x03 && dtoBuffer[3] == 0x02 && dtoBuffer[4] == 0x01);
   // Entry 0 (2 bytes)
   assert(dtoBuffer[5] == 0xAA && dtoBuffer[6] == 0xBB);
   // Entry 1 (4 bytes)
   assert(dtoBuffer[7] == 0x12 && dtoBuffer[8] == 0x34 && dtoBuffer[9] == 0x56 && dtoBuffer[10] == 0x78);

   return true;
}
