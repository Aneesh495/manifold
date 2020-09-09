// tests/test_runner.ec
// Comprehensive test runner and verification harness for manifold.

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

#include "types.eh"
#include "ec_runtime.h"

// Forward declarations of test suites
bool test_byte_buffer_operations(void);
bool test_ring_buffer_operations(void);
bool test_bitstream_intel_and_motorola(void);

bool test_can_frame_and_dlc(void);
bool test_can_crc_algorithms(void);
bool test_can_controller_filters_and_errors(void);
bool test_can_transceiver_and_arbitration(void);
bool test_lin_pid_and_checksum(void);

bool test_isotp_single_frame(void);
bool test_isotp_can_fd_large_single_frame(void);
bool test_isotp_multi_frame_handshake_and_rollover(void);

bool test_dtc_debouncing_and_qualification(void);
bool test_dtc_uds_service_19_and_14(void);
bool test_dtc_flash_storage_persistence(void);

bool test_doip_header_codec_and_nack(void);
bool test_doip_vehicle_discovery(void);
bool test_doip_routing_activation_and_alive_check(void);
bool test_doip_diagnostic_message_routing(void);

bool test_someip_header_and_payload_serialization(void);
bool test_someip_service_discovery_offers_and_queries(void);
bool test_someip_rpc_dispatching_and_notifications(void);

bool test_xcp_connect_status_and_id(void);
bool test_xcp_memory_upload_download_and_checksum(void);
bool test_xcp_cal_page_switching_and_copy(void);
bool test_xcp_dynamic_daq_allocation_and_streaming(void);

// Color codes for ANSI terminal
#define COLOR_GREEN "\033[0;32m"
#define COLOR_RED   "\033[0;31m"
#define COLOR_BLUE  "\033[0;34m"
#define COLOR_BOLD  "\033[1m"
#define COLOR_RESET "\033[0m"

typedef struct TestCase
{
   const char* name;
   bool (*func)(void);
} TestCase;

static const TestCase test_registry[] = {
   { "ByteBuffer dynamic append and bounds", test_byte_buffer_operations },
   { "RingBuffer push/pop and overrun telemetry", test_ring_buffer_operations },
   { "BitStream Intel/Motorola bit extraction and sign extension", test_bitstream_intel_and_motorola },
   { "CAN & CAN FD Frame initialization, padding, and candump", test_can_frame_and_dlc },
   { "CAN CRC-15, CAN FD CRC-17, and CAN FD CRC-21 algorithms", test_can_crc_algorithms },
   { "CAN Controller mailbox filters, TEC/REC, and Bus-Off recovery", test_can_controller_filters_and_errors },
   { "Virtual CAN Transceiver priority arbitration & loopback", test_can_transceiver_and_arbitration },
   { "LIN 2.2 PID parity generation and enhanced checksum", test_lin_pid_and_checksum },
   { "ISO-TP Single Frame (SF) transmission & reassembly", test_isotp_single_frame },
   { "ISO-TP CAN FD Large Single Frame (SF_DL > 7)", test_isotp_can_fd_large_single_frame },
   { "ISO-TP Multi-Frame First Frame, Flow Control CTS & CF rollover", test_isotp_multi_frame_handshake_and_rollover },
   { "DTC status byte transitions and debounce qualification", test_dtc_debouncing_and_qualification },
   { "UDS Service 0x19 (ReadDTC) and Service 0x14 (ClearDTC)", test_dtc_uds_service_19_and_14 },
   { "DTC non-volatile wear-leveling flash persistence", test_dtc_flash_storage_persistence },
   { "DoIP Generic Header encoding, decoding & pattern NACK", test_doip_header_codec_and_nack },
   { "DoIP Vehicle Announcement and EID/VIN discovery filtering", test_doip_vehicle_discovery },
   { "DoIP Routing Activation handshake and alive check watchdog", test_doip_routing_activation_and_alive_check },
   { "DoIP Diagnostic Message encapsulation and logical routing", test_doip_diagnostic_message_routing },
   { "SOME/IP Header framing, byte swapping, and type-safe serializer", test_someip_header_and_payload_serialization },
   { "SOME/IP-SD Offer Service, Find Service, and Eventgroup subscription", test_someip_service_discovery_offers_and_queries },
   { "SOME/IP RPC method dispatching and event notification publish", test_someip_rpc_dispatching_and_notifications },
   { "XCP CONNECT, DISCONNECT, GET_STATUS, and GET_ID state machine", test_xcp_connect_status_and_id },
   { "XCP Memory MTA navigation, UPLOAD, DOWNLOAD, and CHECKSUM", test_xcp_memory_upload_download_and_checksum },
   { "XCP Calibration Page switching, ECU execution mapping & mirroring", test_xcp_cal_page_switching_and_copy },
   { "XCP Dynamic DAQ/ODT allocation and microsecond timestamp streaming", test_xcp_dynamic_daq_allocation_and_streaming },
   { NULL, NULL }
};

int main(int argc, char** argv)
{
   (void)argc;
   (void)argv;

   PrintLn("%s%s================================================================%s", COLOR_BOLD, COLOR_BLUE, COLOR_RESET);
   PrintLn("%s%s       manifold In-Vehicle Gateway Verification Suite           %s", COLOR_BOLD, COLOR_BLUE, COLOR_RESET);
   PrintLn("%s%s================================================================%s", COLOR_BOLD, COLOR_BLUE, COLOR_RESET);

   uint32_t totalPassed = 0;
   uint32_t totalFailed = 0;
   uint64_t startTime = ec_get_time_us();

   for(int i = 0; test_registry[i].name != NULL; i++)
   {
      printf("  [RUN ] %s ... ", test_registry[i].name);
      fflush(stdout);

      bool ok = test_registry[i].func();
      if(ok)
      {
         printf("%s[PASS]%s\n", COLOR_GREEN, COLOR_RESET);
         totalPassed++;
      }
      else
      {
         printf("%s[FAIL]%s\n", COLOR_RED, COLOR_RESET);
         totalFailed++;
      }
   }

   uint64_t durationUs = ec_get_time_us() - startTime;
   PrintLn("----------------------------------------------------------------");
   PrintLn("Test Results: %s%u passed%s, %s%u failed%s in %.2f ms",
           COLOR_GREEN, totalPassed, COLOR_RESET,
           totalFailed > 0 ? COLOR_RED : COLOR_RESET, totalFailed, COLOR_RESET,
           (double)durationUs / 1000.0);
   PrintLn("%s%s================================================================%s", COLOR_BOLD, COLOR_BLUE, COLOR_RESET);

   return (totalFailed == 0) ? 0 : 1;
}
