// include/dbc.eh
// In-Vehicle Signal and DBC database definitions.

#ifndef MANIFOLD_DBC_EH
#define MANIFOLD_DBC_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define DBC_MAX_SIGNAL_NAME         32
#define DBC_MAX_MESSAGE_NAME        32
#define DBC_MAX_SIGNALS_PER_MSG     16
#define DBC_MAX_MESSAGES            32

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

typedef struct DbcDatabase
{
   DbcMessage messages[DBC_MAX_MESSAGES];
   uint32_t messageCount;
} DbcDatabase;

// Function Prototypes

// Signal Codec (SignalCodec.ec)
double dbc_decode_signal(const DbcSignal* sig, const uint8_t* payload, uint32_t payloadLen);
bool dbc_encode_signal(const DbcSignal* sig, double physicalValue, uint8_t* payload, uint32_t payloadLen);

// Database and Parser (DbcParser.ec)
void dbc_database_init(DbcDatabase* db);
bool dbc_database_add_message(DbcDatabase* db, uint32_t id, const char* name, uint8_t dlc, bool isExtended);
bool dbc_database_add_signal(DbcDatabase* db, uint32_t msgId, const char* name, uint32_t startBit, uint32_t bitLength, Endianness endianness, bool isSigned, double factor, double offset, double min, double max, const char* unit);
const DbcMessage* dbc_find_message(const DbcDatabase* db, uint32_t id);
const DbcSignal* dbc_find_signal(const DbcMessage* msg, const char* name);

#endif // MANIFOLD_DBC_EH
