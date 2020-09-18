// src/dbc/DbcParser.ec
// DBC database container, message registry, and signal query interface.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "dbc.eh"
#include "ec_runtime.h"

// Initializes an in-memory DBC database
void dbc_database_init(DbcDatabase* db)
{
   if(!db) return;
   memset(db, 0, sizeof(DbcDatabase));
}

// Registers a CAN/CAN FD message in the database
bool dbc_database_add_message(DbcDatabase* db, uint32_t id, const char* name, uint8_t dlc, bool isExtended)
{
   if(!db || db->messageCount >= DBC_MAX_MESSAGES)
   {
      return false;
   }

   DbcMessage* msg = &db->messages[db->messageCount++];
   msg->id = id;
   if(name)
   {
      strncpy(msg->name, name, DBC_MAX_MESSAGE_NAME - 1);
      msg->name[DBC_MAX_MESSAGE_NAME - 1] = '\0';
   }
   msg->dlc = dlc;
   msg->isExtended = isExtended;
   msg->signalCount = 0;

   return true;
}

// Registers a signal within an existing message
bool dbc_database_add_signal(DbcDatabase* db, uint32_t msgId, const char* name, uint32_t startBit, uint32_t bitLength, Endianness endianness, bool isSigned, double factor, double offset, double min, double max, const char* unit)
{
   if(!db || !name) return false;

   DbcMessage* msg = NULL;
   for(uint32_t i = 0; i < db->messageCount; i++)
   {
      if(db->messages[i].id == msgId)
      {
         msg = &db->messages[i];
         break;
      }
   }

   if(!msg || msg->signalCount >= DBC_MAX_SIGNALS_PER_MSG)
   {
      return false;
   }

   DbcSignal* sig = &msg->signals[msg->signalCount++];
   strncpy(sig->name, name, DBC_MAX_SIGNAL_NAME - 1);
   sig->name[DBC_MAX_SIGNAL_NAME - 1] = '\0';
   sig->startBit   = startBit;
   sig->bitLength  = bitLength;
   sig->endianness = endianness;
   sig->isSigned   = isSigned;
   sig->factor     = (factor == 0.0) ? 1.0 : factor;
   sig->offset     = offset;
   sig->min        = min;
   sig->max        = max;

   if(unit)
   {
      strncpy(sig->unit, unit, sizeof(sig->unit) - 1);
      sig->unit[sizeof(sig->unit) - 1] = '\0';
   }

   return true;
}

// Looks up a message definition by CAN identifier
const DbcMessage* dbc_find_message(const DbcDatabase* db, uint32_t id)
{
   if(!db) return NULL;
   for(uint32_t i = 0; i < db->messageCount; i++)
   {
      if(db->messages[i].id == id)
      {
         return &db->messages[i];
      }
   }
   return NULL;
}

// Looks up a signal within a message by signal name
const DbcSignal* dbc_find_signal(const DbcMessage* msg, const char* name)
{
   if(!msg || !name) return NULL;
   for(uint32_t i = 0; i < msg->signalCount; i++)
   {
      if(strncmp(msg->signals[i].name, name, DBC_MAX_SIGNAL_NAME) == 0)
      {
         return &msg->signals[i];
      }
   }
   return NULL;
}
