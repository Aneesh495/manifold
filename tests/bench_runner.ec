// tests/bench_runner.ec
// Latency and throughput benchmark runner for manifold.

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

#include "types.eh"
#include "ec_runtime.h"

int main(int argc, char** argv)
{
   (void)argc;
   (void)argv;

   PrintLn("==================================================================");
   PrintLn(" manifold Performance & Latency Benchmark Harness");
   PrintLn("==================================================================");
   PrintLn("Benchmark initialized.");
   return 0;
}
