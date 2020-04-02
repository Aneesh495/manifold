// src/app/DiagTerminal.ec
// Interactive in-vehicle diagnostic and bus inspection terminal.

#include <stdio.h>
#include <stdbool.h>

#include "types.eh"
#include "ec_runtime.h"

int main(int argc, char** argv)
{
   (void)argc;
   (void)argv;

   PrintLn("==================================================================");
   PrintLn(" manifold Interactive Diagnostic & Bus Inspection Terminal");
   PrintLn("==================================================================");
   PrintLn("Terminal ready. Type 'help' for available commands.");
   return 0;
}
