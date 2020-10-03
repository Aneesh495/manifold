// src/app/DiagTerminal.ec
// Interactive in-vehicle diagnostic and bus inspection terminal.

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#include "types.eh"
#include "can.eh"
#include "isotp.eh"
#include "uds.eh"
#include "doip.eh"
#include "someip.eh"
#include "xcp.eh"
#include "dtc.eh"
#include "routing.eh"
#include "ec_runtime.h"

// Forward declarations from DTC and UDS subsystems
FaultManager* uds_get_fault_manager(void);
void fault_manager_init(FaultManager* mgr);
DtcEntry* fault_manager_add_dtc(FaultManager* mgr, uint32_t code, int8_t failStep, int8_t passStep);
void fault_manager_report_test_result(FaultManager* mgr, uint32_t code, bool failed);

#define COLOR_GREEN "\033[0;32m"
#define COLOR_RED   "\033[0;31m"
#define COLOR_BLUE  "\033[0;34m"
#define COLOR_CYAN  "\033[0;36m"
#define COLOR_YELLOW "\033[0;33m"
#define COLOR_BOLD  "\033[1m"
#define COLOR_RESET "\033[0m"

static UdsServer g_terminalUds;
static DoipNode g_terminalDoip;
static XcpServer g_terminalXcp;

static void print_banner(void)
{
   printf("%s==================================================================%s\n", COLOR_CYAN, COLOR_RESET);
   printf("%s   manifold Diagnostic Terminal & In-Vehicle Bus Monitor CLI      %s\n", COLOR_BOLD, COLOR_RESET);
   printf("%s   ISO 14229 UDS | ISO 13400 DoIP | SOME/IP | ASAM XCP Engine    %s\n", COLOR_CYAN, COLOR_RESET);
   printf("%s==================================================================%s\n", COLOR_CYAN, COLOR_RESET);
   printf("Type '%shelp%s' for available commands or '%sexit%s' to quit.\n\n", COLOR_GREEN, COLOR_RESET, COLOR_RED, COLOR_RESET);
}

static void print_help(void)
{
   printf("\n%sAvailable Commands:%s\n", COLOR_BOLD, COLOR_RESET);
   printf("  %suds session [default|programming|extended]%s : Transition UDS session (0x10)\n", COLOR_GREEN, COLOR_RESET);
   printf("  %suds read-did <HEX_DID>%s                     : Read Data By Identifier (0x22)\n", COLOR_GREEN, COLOR_RESET);
   printf("  %suds write-did <HEX_DID> <HEX_BYTES>%s        : Write Data By Identifier (0x2E)\n", COLOR_GREEN, COLOR_RESET);
   printf("  %suds read-dtc [all|confirmed|pending]%s       : Read DTC Information (0x19)\n", COLOR_GREEN, COLOR_RESET);
   printf("  %suds clear-dtc [all|<HEX_DTC>]%s              : Clear Diagnostic Info (0x14)\n", COLOR_GREEN, COLOR_RESET);
   printf("  %suds security <level>%s                       : Perform SecurityAccess handshake (0x27)\n", COLOR_GREEN, COLOR_RESET);
   printf("  %sdoip announce%s                              : Broadcast Vehicle Announcement (0x0004)\n", COLOR_CYAN, COLOR_RESET);
   printf("  %sdoip activate <HEX_SA>%s                     : Perform DoIP Routing Activation (0x0005)\n", COLOR_CYAN, COLOR_RESET);
   printf("  %sxcp connect%s                                : Establish ASAM XCP calibration session\n", COLOR_YELLOW, COLOR_RESET);
   printf("  %sxcp read <HEX_ADDR> <NUM_BYTES>%s            : Short upload memory inspection (0xF4)\n", COLOR_YELLOW, COLOR_RESET);
   printf("  %sxcp page [flash|ram]%s                       : Switch active ECU calibration page (0xEB)\n", COLOR_YELLOW, COLOR_RESET);
   printf("  %sstatus%s                                     : Display gateway bus controllers & statistics\n", COLOR_BOLD, COLOR_RESET);
   printf("  %shelp%s                                       : Print this command guide\n", COLOR_BOLD, COLOR_RESET);
   printf("  %sexit%s                                       : Exit diagnostic terminal\n\n", COLOR_RED, COLOR_RESET);
}

static void print_hex_dump(const char* label, const uint8_t* data, uint32_t len)
{
   printf("%s%s (%u bytes):%s", COLOR_BOLD, label, len, COLOR_RESET);
   for(uint32_t i = 0; i < len; i++)
   {
      if(i % 16 == 0) printf("\n  %04X: ", i);
      printf("%02X ", data[i]);
   }
   printf("\n");
}

static void handle_uds_session(const char* arg)
{
   uint8_t sub = 0x01;
   if(strcmp(arg, "programming") == 0) sub = 0x02;
   else if(strcmp(arg, "extended") == 0) sub = 0x03;

   uint8_t req[2] = { UDS_SID_DIAGNOSTIC_SESSION_CONTROL, sub };
   uint8_t resp[256];
   uint32_t respLen = 0;

   uds_server_process_request(&g_terminalUds, req, 2, resp, &respLen);
   if(respLen > 0 && resp[0] == 0x50)
   {
      printf("%s[UDS 0x10 SUCCESS]%s Session transitioned to %s (0x%02X)\n", COLOR_GREEN, COLOR_RESET, arg, sub);
      print_hex_dump("Positive Response", resp, respLen);
   }
   else
   {
      printf("%s[UDS 0x10 REJECTED]%s NRC: 0x%02X\n", COLOR_RED, COLOR_RESET, (respLen >= 3) ? resp[2] : 0xFF);
   }
}

static void handle_uds_read_did(const char* arg)
{
   uint32_t did = (uint32_t)strtoul(arg, NULL, 16);
   uint8_t req[3] = { UDS_SID_READ_DATA_BY_IDENTIFIER, (uint8_t)((did >> 8) & 0xFF), (uint8_t)(did & 0xFF) };
   uint8_t resp[256];
   uint32_t respLen = 0;

   uds_server_process_request(&g_terminalUds, req, 3, resp, &respLen);
   if(respLen > 0 && resp[0] == 0x62)
   {
      printf("%s[UDS 0x22 SUCCESS]%s Read DID 0x%04X\n", COLOR_GREEN, COLOR_RESET, did);
      print_hex_dump("Payload Data", resp + 3, respLen - 3);
   }
   else
   {
      printf("%s[UDS 0x22 REJECTED]%s NRC: 0x%02X\n", COLOR_RED, COLOR_RESET, (respLen >= 3) ? resp[2] : 0xFF);
   }
}

static void handle_uds_read_dtc(const char* arg)
{
   uint8_t mask = 0xFF;
   if(strcmp(arg, "confirmed") == 0) mask = 0x08;
   else if(strcmp(arg, "pending") == 0) mask = 0x04;

   uint8_t req[3] = { UDS_SID_READ_DTC_INFORMATION, 0x02, mask };
   uint8_t resp[256];
   uint32_t respLen = 0;

   uds_server_process_request(&g_terminalUds, req, 3, resp, &respLen);
   if(respLen > 0 && resp[0] == 0x59)
   {
      uint32_t dtcCount = (respLen >= 3) ? (respLen - 3) / 4 : 0;
      printf("%s[UDS 0x19 SUCCESS]%s Found %u matching DTCs (Availability Mask: 0x%02X)\n", COLOR_GREEN, COLOR_RESET, dtcCount, resp[2]);
      for(uint32_t i = 0; i < dtcCount; i++)
      {
         uint32_t offset = 3 + (i * 4);
         uint32_t code = ((uint32_t)resp[offset] << 16) | ((uint32_t)resp[offset + 1] << 8) | resp[offset + 2];
         uint8_t status = resp[offset + 3];
         printf("  DTC #%u: 0x%06X | Status: 0x%02X [Conf: %d, Pend: %d, TestFail: %d]\n",
                i + 1, code, status, (status & 0x08) ? 1 : 0, (status & 0x04) ? 1 : 0, (status & 0x01) ? 1 : 0);
      }
   }
   else
   {
      printf("%s[UDS 0x19 REJECTED]%s NRC: 0x%02X\n", COLOR_RED, COLOR_RESET, (respLen >= 3) ? resp[2] : 0xFF);
   }
}

static void handle_uds_clear_dtc(const char* arg)
{
   uint32_t group = 0xFFFFFF;
   if(strcmp(arg, "all") != 0 && strlen(arg) > 0)
   {
      group = (uint32_t)strtoul(arg, NULL, 16);
   }

   uint8_t req[4] = { UDS_SID_CLEAR_DIAGNOSTIC_INFORMATION, (uint8_t)((group >> 16) & 0xFF), (uint8_t)((group >> 8) & 0xFF), (uint8_t)(group & 0xFF) };
   uint8_t resp[256];
   uint32_t respLen = 0;

   uds_server_process_request(&g_terminalUds, req, 4, resp, &respLen);
   if(respLen > 0 && resp[0] == 0x54)
   {
      printf("%s[UDS 0x14 SUCCESS]%s Diagnostic fault memory cleared for group 0x%06X\n", COLOR_GREEN, COLOR_RESET, group);
   }
   else
   {
      printf("%s[UDS 0x14 REJECTED]%s NRC: 0x%02X\n", COLOR_RED, COLOR_RESET, (respLen >= 3) ? resp[2] : 0xFF);
   }
}

static void handle_doip_announce(void)
{
   uint8_t outBuf[64];
   uint32_t len = doip_build_vehicle_announcement(&g_terminalDoip, outBuf, sizeof(outBuf));
   if(len > 0)
   {
      printf("%s[DoIP ANNOUNCEMENT BROADCAST]%s Length: %u bytes\n", COLOR_CYAN, COLOR_RESET, len);
      printf("  VIN: %s | Logical Address: 0x%04X\n", g_terminalDoip.vin, g_terminalDoip.logicalAddress);
      print_hex_dump("DoIP Wire Packet", outBuf, len);
   }
}

static void handle_doip_activate(const char* arg)
{
   uint16_t sa = (uint16_t)strtoul(arg, NULL, 16);
   uint8_t actReq[7] = { (uint8_t)((sa >> 8) & 0xFF), (uint8_t)(sa & 0xFF), 0x00, 0, 0, 0, 0 };
   uint8_t respBuf[64];
   uint32_t len = doip_process_routing_activation(&g_terminalDoip, 1, actReq, sizeof(actReq), respBuf, sizeof(respBuf));

   if(len > 0 && respBuf[12] == DOIP_ROUTING_SUCCESS)
   {
      printf("%s[DoIP ACTIVATION SUCCESS]%s Registered Client SA 0x%04X to Gateway\n", COLOR_GREEN, COLOR_RESET, sa);
   }
   else
   {
      printf("%s[DoIP ACTIVATION REJECTED]%s Code: 0x%02X\n", COLOR_RED, COLOR_RESET, (len >= 13) ? respBuf[12] : 0xFF);
   }
}

static void handle_xcp_connect(void)
{
   uint8_t connectCmd[2] = { XCP_CMD_CONNECT, 0x00 };
   uint8_t resp[64];
   uint32_t len = xcp_process_command(&g_terminalXcp, connectCmd, 2, resp, sizeof(resp));

   if(len >= 8 && resp[0] == XCP_PID_CMD_RESPONSE)
   {
      printf("%s[ASAM XCP CONNECTED]%s Resources: 0x%02X | Max CTO: %u | Max DTO: %u\n",
             COLOR_YELLOW, COLOR_RESET, resp[1], resp[3], ((uint16_t)resp[5] << 8) | resp[4]);
   }
   else
   {
      printf("%s[XCP CONNECT FAILED]%s\n", COLOR_RED, COLOR_RESET);
   }
}

static void handle_xcp_read(const char* addrStr, const char* lenStr)
{
   uint32_t addr = (uint32_t)strtoul(addrStr, NULL, 16);
   uint8_t numBytes = (uint8_t)strtoul(lenStr, NULL, 10);
   if(numBytes == 0) numBytes = 4;

   uint8_t shortUpCmd[8] = {
      XCP_CMD_SHORT_UPLOAD, numBytes, 0x00, 0x00,
      (uint8_t)(addr & 0xFF), (uint8_t)((addr >> 8) & 0xFF),
      (uint8_t)((addr >> 16) & 0xFF), (uint8_t)((addr >> 24) & 0xFF)
   };

   uint8_t resp[64];
   uint32_t len = xcp_process_command(&g_terminalXcp, shortUpCmd, 8, resp, sizeof(resp));
   if(len > 1 && resp[0] == XCP_PID_CMD_RESPONSE)
   {
      printf("%s[XCP SHORT_UPLOAD 0x%08X]%s %u bytes:\n", COLOR_YELLOW, addr, COLOR_RESET, numBytes);
      print_hex_dump("Memory Contents", resp + 1, numBytes);
   }
   else
   {
      printf("%s[XCP READ ERROR]%s Code: 0x%02X\n", COLOR_RED, COLOR_RESET, (len >= 2) ? resp[1] : 0xFF);
   }
}

static void handle_status(void)
{
   printf("\n%s--- manifold Central Gateway Status ---%s\n", COLOR_BOLD, COLOR_RESET);
   printf("  ECU Logical Address : 0x%04X (DoIP Gateway Node)\n", g_terminalDoip.logicalAddress);
   printf("  Vehicle VIN         : %s\n", g_terminalDoip.vin);
   printf("  Active UDS Session  : 0x%02X\n", (uint8_t)g_terminalUds.currentSession);
   printf("  UDS Security Level  : 0x%02X\n", g_terminalUds.security.currentLevel);
   printf("  Fault Memory Count  : %u active DTC records\n", uds_get_fault_manager()->count);
   printf("  XCP Session State   : %s\n", g_terminalXcp.isConnected ? "CONNECTED" : "STANDBY");
   printf("  XCP Active Page     : ECU=%s, Tool=%s\n",
          g_terminalXcp.ecuCalPage == 0 ? "FLASH" : "RAM",
          g_terminalXcp.xcpCalPage == 0 ? "FLASH" : "RAM");
   printf("----------------------------------------\n\n");
}

static void execute_command(char* line)
{
   char* cmd = strtok(line, " \t\r\n");
   if(!cmd || strlen(cmd) == 0) return;

   if(strcmp(cmd, "help") == 0)
   {
      print_help();
   }
   else if(strcmp(cmd, "status") == 0)
   {
      handle_status();
   }
   else if(strcmp(cmd, "uds") == 0)
   {
      char* sub = strtok(NULL, " \t\r\n");
      if(!sub) { printf("Missing UDS subcommand. Type 'help' for usage.\n"); return; }

      if(strcmp(sub, "session") == 0)
      {
         char* sType = strtok(NULL, " \t\r\n");
         handle_uds_session(sType ? sType : "default");
      }
      else if(strcmp(sub, "read-did") == 0)
      {
         char* didStr = strtok(NULL, " \t\r\n");
         if(!didStr) { printf("Missing DID. Example: uds read-did F190\n"); return; }
         handle_uds_read_did(didStr);
      }
      else if(strcmp(sub, "read-dtc") == 0)
      {
         char* maskStr = strtok(NULL, " \t\r\n");
         handle_uds_read_dtc(maskStr ? maskStr : "all");
      }
      else if(strcmp(sub, "clear-dtc") == 0)
      {
         char* groupStr = strtok(NULL, " \t\r\n");
         handle_uds_clear_dtc(groupStr ? groupStr : "all");
      }
      else
      {
         printf("Unknown UDS service '%s'. Type 'help' for usage.\n", sub);
      }
   }
   else if(strcmp(cmd, "doip") == 0)
   {
      char* sub = strtok(NULL, " \t\r\n");
      if(!sub) { printf("Missing DoIP subcommand. Type 'help' for usage.\n"); return; }

      if(strcmp(sub, "announce") == 0)
      {
         handle_doip_announce();
      }
      else if(strcmp(sub, "activate") == 0)
      {
         char* saStr = strtok(NULL, " \t\r\n");
         handle_doip_activate(saStr ? saStr : "0E00");
      }
      else
      {
         printf("Unknown DoIP command '%s'.\n", sub);
      }
   }
   else if(strcmp(cmd, "xcp") == 0)
   {
      char* sub = strtok(NULL, " \t\r\n");
      if(!sub) { printf("Missing XCP subcommand. Type 'help' for usage.\n"); return; }

      if(strcmp(sub, "connect") == 0)
      {
         handle_xcp_connect();
      }
      else if(strcmp(sub, "read") == 0)
      {
         char* addrStr = strtok(NULL, " \t\r\n");
         char* lenStr = strtok(NULL, " \t\r\n");
         if(!addrStr) { printf("Missing address. Example: xcp read 00000100 4\n"); return; }
         handle_xcp_read(addrStr, lenStr ? lenStr : "4");
      }
      else
      {
         printf("Unknown XCP command '%s'.\n", sub);
      }
   }
   else if(strcmp(cmd, "exit") == 0 || strcmp(cmd, "quit") == 0)
   {
      printf("Terminating diagnostic session. Goodbye.\n");
      exit(0);
   }
   else
   {
      printf("Unknown command '%s'. Type 'help' for available commands.\n", cmd);
   }
}

int main(int argc, char** argv)
{
   uds_server_init(&g_terminalUds);
   const uint8_t testEid[6] = { 0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E };
   const uint8_t testGid[6] = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
   doip_node_init(&g_terminalDoip, "WAUZZZ8V1GA000001", 0x0E80, testEid, testGid);
   xcp_server_init(&g_terminalXcp);

   // Populate sample DTCs
   FaultManager* fm = uds_get_fault_manager();
   fault_manager_init(fm);
   fault_manager_add_dtc(fm, 0x010000, 30, -10);
   fault_manager_report_test_result(fm, 0x010000, true);
   fault_manager_report_test_result(fm, 0x010000, true);
   fault_manager_report_test_result(fm, 0x010000, true); // Qualifies

   print_banner();

   // Non-interactive batch execution mode (e.g. ./manifold_terminal -c "uds session extended")
   if(argc >= 3 && strcmp(argv[1], "-c") == 0)
   {
      char buffer[512];
      strncpy(buffer, argv[2], sizeof(buffer) - 1);
      buffer[sizeof(buffer) - 1] = '\0';
      printf("%smanifold> %s%s\n", COLOR_GREEN, buffer, COLOR_RESET);
      execute_command(buffer);
      return 0;
   }

   // Default interactive session loop
   char line[512];
   while(1)
   {
      printf("%smanifold> %s", COLOR_GREEN, COLOR_RESET);
      if(!fgets(line, sizeof(line), stdin))
      {
         break;
      }
      execute_command(line);
   }

   return 0;
}
