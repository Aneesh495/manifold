// src/main.ec
// Central Gateway daemon entrypoint for manifold.

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
   PrintLn(" manifold In-Vehicle Network Central Gateway v1.0.0");
   PrintLn(" CAN FD / SOME/IP / LIN Router & Diagnostic Calibration Kernel");
   PrintLn("==================================================================");
   PrintLn("Gateway daemon initialized.");
   return 0;
}
