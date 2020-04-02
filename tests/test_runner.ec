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

static const TestCase core_tests[] = {
   { "ByteBuffer dynamic append and bounds", test_byte_buffer_operations },
   { "RingBuffer push/pop and overrun telemetry", test_ring_buffer_operations },
   { "BitStream Intel/Motorola bit extraction and sign extension", test_bitstream_intel_and_motorola },
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

   for(int i = 0; core_tests[i].name != NULL; i++)
   {
      printf("  [RUN ] %s ... ", core_tests[i].name);
      fflush(stdout);

      bool ok = core_tests[i].func();
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
