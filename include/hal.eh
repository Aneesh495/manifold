// include/hal.eh
// Hardware abstraction layer for virtual automotive communication buses.

#ifndef MANIFOLD_HAL_EH
#define MANIFOLD_HAL_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"
#include "can.eh"

typedef struct VirtualBus
{
   uint32_t busId;
   char name[32];
   bool isOpen;
   uint64_t rxFrames;
   uint64_t txFrames;
   uint64_t errorFrames;
} VirtualBus;

bool hal_bus_open(VirtualBus* bus, uint32_t busId, const char* name);
bool hal_bus_close(VirtualBus* bus);
bool hal_bus_transmit(VirtualBus* bus, const CanFrame* frame);
bool hal_bus_receive(VirtualBus* bus, CanFrame* outFrame);

#endif // MANIFOLD_HAL_EH
