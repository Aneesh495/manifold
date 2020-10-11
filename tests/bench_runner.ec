// tests/bench_runner.ec
// Latency and throughput benchmark harness for manifold in-vehicle network gateway.

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#include "types.eh"
#include "can.eh"
#include "routing.eh"
#include "someip.eh"
#include "secoc.eh"
#include "ec_runtime.h"

#define COLOR_GREEN  "\033[0;32m"
#define COLOR_CYAN   "\033[0;36m"
#define COLOR_BOLD   "\033[1m"
#define COLOR_RESET  "\033[0m"

static double get_time_sec(void)
{
   return (double)ec_get_time_us() / 1000000.0;
}

static void bench_can_fd_crc(uint32_t iterations)
{
   uint8_t sampleData[64];
   for(uint32_t i = 0; i < 64; i++) sampleData[i] = (uint8_t)(i * 3 + 7);

   double start = get_time_sec();
   volatile uint32_t crcAccum = 0;

   for(uint32_t i = 0; i < iterations; i++)
   {
      crcAccum ^= can_fd_crc21(sampleData, 64, 0x05);
   }

   double elapsed = get_time_sec() - start;
   double mops = ((double)iterations / elapsed) / 1000000.0;
   double mbSec = (((double)iterations * 64.0) / elapsed) / (1024.0 * 1024.0);

   printf("  %-34s %10u %11.2f ms %10.2f Mops/s (%6.1f MB/s)\n",
          "CAN FD CRC-21 Engine", iterations, elapsed * 1000.0, mops, mbSec);
}

static void bench_secoc_cmac(uint32_t iterations)
{
   SecOcConfig cfg;
   cfg.dataId = 0x1000;
   const uint8_t key[16] = {
      0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
      0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
   };
   memcpy(cfg.key, key, 16);
   cfg.macTruncationBits = 64;
   cfg.freshnessBits = 64;

   uint8_t data[16] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
   uint8_t outMac[8];

   double start = get_time_sec();
   for(uint32_t i = 0; i < iterations; i++)
   {
      secoc_generate_mac(&cfg, data, 16, i, outMac);
   }

   double elapsed = get_time_sec() - start;
   double kops = ((double)iterations / elapsed) / 1000.0;

   printf("  %-34s %10u %11.2f ms %10.2f Kops/s\n",
          "SecOC AES-128 CMAC Signatures", iterations, elapsed * 1000.0, kops);
}

static void bench_routing_table(uint32_t iterations)
{
   RoutingTable table;
   routing_table_init(&table);

   // Populate 64 routing rules across domains
   for(uint32_t i = 0; i < 64; i++)
   {
      routing_table_add_rule(&table, (BusDomain)(i % 4), 0x100 + i, 0x7F0,
                             (BusDomain)((i + 1) % 4), 0x200 + i, ROUTE_ACTION_TRANSLATE_ID, i);
   }

   double start = get_time_sec();
   volatile const RouteRule* r = NULL;

   for(uint32_t i = 0; i < iterations; i++)
   {
      uint32_t testId = 0x100 + (i & 0x3F);
      r = routing_table_match(&table, (BusDomain)(i & 0x03), testId);
   }
   (void)r;

   double elapsed = get_time_sec() - start;
   double mops = ((double)iterations / elapsed) / 1000000.0;

   printf("  %-34s %10u %11.2f ms %10.2f Mops/s\n",
          "Gateway Bitmask Route Match", iterations, elapsed * 1000.0, mops);
}

static void bench_someip_serializer(uint32_t iterations)
{
   uint8_t buffer[256];
   SomeIpSerializer ser;
   SomeIpDeserializer des;

   double start = get_time_sec();

   for(uint32_t i = 0; i < iterations; i++)
   {
      someip_serializer_init(&ser, buffer, sizeof(buffer));
      someip_serialize_uint32(&ser, 0x12345678);
      someip_serialize_float32(&ser, 88.5f);
      someip_serialize_uint64(&ser, 0xDEADBEEFCAFEBABEULL);

      someip_deserializer_init(&des, buffer, ser.offset);
      uint32_t u32;
      float f32;
      uint64_t u64;
      someip_deserialize_uint32(&des, &u32);
      someip_deserialize_float32(&des, &f32);
      someip_deserialize_uint64(&des, &u64);
   }

   double elapsed = get_time_sec() - start;
   double mops = ((double)iterations / elapsed) / 1000000.0;

   printf("  %-34s %10u %11.2f ms %10.2f Mops/s\n",
          "SOME/IP Type-Safe Serialization", iterations, elapsed * 1000.0, mops);
}

int main(int argc, char** argv)
{
   (void)argc;
   (void)argv;

   printf("\n%s========================================================================================%s\n", COLOR_CYAN, COLOR_RESET);
   printf("%s           manifold High-Throughput In-Vehicle Gateway Benchmark Suite          %s\n", COLOR_BOLD, COLOR_RESET);
   printf("%s========================================================================================%s\n", COLOR_CYAN, COLOR_RESET);
   printf("  %-34s %10s %14s %18s\n", "Benchmark Subsystem", "Iterations", "Elapsed Time", "Throughput");
   printf("  --------------------------------------------------------------------------------------\n");

   bench_can_fd_crc(500000);
   bench_secoc_cmac(50000);
   bench_routing_table(1000000);
   bench_someip_serializer(500000);

   printf("%s========================================================================================%s\n\n", COLOR_CYAN, COLOR_RESET);
   return 0;
}
