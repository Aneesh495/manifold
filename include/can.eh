// include/can.eh
// CAN 2.0B and CAN FD frame definitions, CRC algorithms, and controller state machines.

#ifndef MANIFOLD_CAN_EH
#define MANIFOLD_CAN_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"

#define CAN_MAX_STANDARD_DLC 8
#define CAN_FD_MAX_DLC 15
#define CAN_FD_MAX_DATA_LEN 64

// CAN Controller Operating States
typedef enum CanControllerState
{
   CAN_STATE_ERROR_ACTIVE = 0,
   CAN_STATE_ERROR_PASSIVE = 1,
   CAN_STATE_BUS_OFF = 2,
   CAN_STATE_SLEEP = 3
} CanControllerState;

// CAN Frame Structure supporting both Classical CAN and CAN FD
typedef struct CanFrame
{
   uint32_t arbitrationId; // 11-bit or 29-bit identifier
   uint8_t dlc;            // Data Length Code (0 to 15)
   uint8_t payloadLength;  // Actual bytes (0 to 64)
   uint8_t data[CAN_FD_MAX_DATA_LEN];
   CanIdFlags flags;
   Timestamp timestamp;
   uint32_t crc;           // Computed frame CRC (CRC-15, CRC-17, or CRC-21)
} CanFrame;

// DLC to Length mapping table (ISO 11898-1:2015)
static inline uint8_t can_fd_dlc_to_len(uint8_t dlc)
{
   static const uint8_t dlc_table[16] = {
      0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 16, 20, 24, 32, 48, 64
   };
   return (dlc <= 15) ? dlc_table[dlc] : 64;
}

// Length to DLC mapping table
static inline uint8_t can_fd_len_to_dlc(uint8_t len)
{
   if(len <= 8) return len;
   if(len <= 12) return 9;
   if(len <= 16) return 10;
   if(len <= 20) return 11;
   if(len <= 24) return 12;
   if(len <= 32) return 13;
   if(len <= 48) return 14;
   return 15;
}

// Frame initialization helper
void can_frame_init(CanFrame* frame, uint32_t id, bool isExtended, bool isFd);
bool can_frame_set_payload(CanFrame* frame, const uint8_t* payload, uint8_t len);

// CRC calculations
uint16_t can_crc15(const uint8_t* data, uint32_t len);
uint32_t can_fd_crc17(const uint8_t* data, uint32_t len, uint8_t stuffCount);
uint32_t can_fd_crc21(const uint8_t* data, uint32_t len, uint8_t stuffCount);

#endif // MANIFOLD_CAN_EH
