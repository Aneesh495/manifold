// include/dbc.eh
// In-Vehicle Signal and DBC database definitions.

#ifndef MANIFOLD_DBC_EH
#define MANIFOLD_DBC_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define DBC_MAX_SIGNAL_NAME 32
#define DBC_MAX_MESSAGE_NAME 32
#define DBC_MAX_SIGNALS_PER_MSG 16

typedef struct DbcSignal
{
   char name[DBC_MAX_SIGNAL_NAME];
   uint32_t startBit;
   uint32_t bitLength;
   Endianness endianness;
   bool isSigned;
   double factor;
   double offset;
   double min;
   double max;
   char unit[16];
} DbcSignal;

typedef struct DbcMessage
{
   uint32_t id;
   char name[DBC_MAX_MESSAGE_NAME];
   uint8_t dlc;
   bool isExtended;
   DbcSignal signals[DBC_MAX_SIGNALS_PER_MSG];
   uint8_t signalCount;
} DbcMessage;

#endif // MANIFOLD_DBC_EH
