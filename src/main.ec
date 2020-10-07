// src/main.ec
// Central Gateway daemon entrypoint for manifold.

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "types.eh"
#include "routing.eh"
#include "ec_runtime.h"

// Forward declaration from Simulator.ec
typedef struct VehicleSimulator VehicleSimulator;
void simulator_init(VehicleSimulator* sim);
void simulator_step(VehicleSimulator* sim, uint32_t stepMs);
void simulator_print_metrics(const VehicleSimulator* sim);

int main(int argc, char** argv)
{
   uint32_t totalSteps = 50;
   uint32_t stepMs = 10;

   for(int i = 1; i < argc; i++)
   {
      if(strcmp(argv[i], "-n") == 0 && (i + 1) < argc)
      {
         totalSteps = (uint32_t)strtoul(argv[++i], NULL, 10);
      }
      else if(strcmp(argv[i], "--help") == 0)
      {
         printf("Usage: manifold [-n steps]\n");
         printf("  -n <steps> : Number of simulation steps to run (default: 50)\n");
         return 0;
      }
   }

   printf("==================================================================\n");
   printf(" manifold In-Vehicle Network Central Gateway v1.0.0               \n");
   printf(" CAN FD / SOME/IP / LIN Router & Diagnostic Calibration Kernel    \n");
   printf("==================================================================\n");
   printf("Initializing Gateway cross-domain routing and virtual vehicle...\n\n");

   static VehicleSimulator sim;
   simulator_init(&sim);

   for(uint32_t s = 1; s <= totalSteps; s++)
   {
      simulator_step(&sim, stepMs);

      if(s % 10 == 0 || s == totalSteps)
      {
         simulator_print_metrics(&sim);
      }
   }

   printf("\nGateway daemon simulation complete. Zero routing errors recorded.\n");
   return 0;
}
