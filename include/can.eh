// include/can.eh
// CAN 2.0B and CAN FD frame definitions, CRC algorithms, and controller state machines.

#ifndef MANIFOLD_CAN_EH
#define MANIFOLD_CAN_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"
#include "core.eh"

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
int can_frame_to_candump(const CanFrame* frame, const char* interfaceName, char* outBuf, size_t bufSize);

// CRC calculations
uint16_t can_crc15(const uint8_t* data, uint32_t len);
uint32_t can_fd_crc17(const uint8_t* data, uint32_t len, uint8_t stuffCount);
uint32_t can_fd_crc21(const uint8_t* data, uint32_t len, uint8_t stuffCount);
uint32_t can_frame_compute_crc(CanFrame* frame, uint8_t stuffCount);
bool can_frame_verify_crc(const CanFrame* frame, uint8_t stuffCount, uint32_t expectedCrc);

// Controller Mailbox and Filter Definitions
#define CAN_CONTROLLER_MAX_MAILBOXES 32
#define CAN_CONTROLLER_MAX_FILTERS   16

typedef enum MailboxType
{
   MAILBOX_TYPE_UNUSED = 0,
   MAILBOX_TYPE_RX     = 1,
   MAILBOX_TYPE_TX     = 2
} MailboxType;

typedef struct CanFilter
{
   bool isActive;
   bool isExtended;
   uint32_t filterId;
   uint32_t filterMask;
} CanFilter;

typedef struct CanMailbox
{
   MailboxType type;
   CanFrame frame;
   bool isPending;
   bool isLocked;
   uint32_t priority;
} CanMailbox;

typedef struct CanController
{
   uint32_t controllerId;
   CanControllerState state;
   uint16_t tec;               // Transmit Error Counter
   uint16_t rec;               // Receive Error Counter
   uint32_t errorFrames;
   uint32_t busOffCount;
   uint32_t busOffRecoveryCounter;
   CanMailbox mailboxes[CAN_CONTROLLER_MAX_MAILBOXES];
   CanFilter filters[CAN_CONTROLLER_MAX_FILTERS];
   uint32_t totalTransmitted;
   uint32_t totalReceived;
} CanController;

void can_controller_init(CanController* ctrl, uint32_t id);
bool can_controller_add_filter(CanController* ctrl, uint32_t filterId, uint32_t filterMask, bool isExtended);
bool can_controller_matches_filter(const CanController* ctrl, const CanFrame* frame);
bool can_controller_send_frame(CanController* ctrl, const CanFrame* frame);
bool can_controller_receive_frame(CanController* ctrl, const CanFrame* frame);
void can_controller_record_tx_error(CanController* ctrl);
void can_controller_record_rx_error(CanController* ctrl);
bool can_controller_recover_bus_off(CanController* ctrl);

// Transceiver
typedef struct CanTransceiver
{
   uint32_t busId;
   char busName[32];
   RingBuffer* txQueue;
   RingBuffer* rxQueue;
   bool isLoopbackEnabled;
   uint64_t totalFramesBroadcast;
   uint64_t totalFramesReceived;
   uint64_t arbitrationLossCount;
} CanTransceiver;

CanTransceiver* can_transceiver_create(uint32_t busId, const char* name, bool loopback);
void can_transceiver_destroy(CanTransceiver* xcvr);
bool can_transceiver_transmit(CanTransceiver* xcvr, const CanFrame* frame);
bool can_transceiver_receive(CanTransceiver* xcvr, CanFrame* outFrame);
CanFrame* can_transceiver_arbitrate(CanFrame** pendingFrames, uint32_t count, uint32_t* winningIdx);

// LIN Master definitions
#define LIN_MAX_DATA_BYTES 8
#define LIN_MAX_SCHEDULE_ENTRIES 32

typedef struct LinFrame
{
   uint8_t frameId;      // 6-bit ID (0 to 63)
   uint8_t protectedId;  // 8-bit PID with parity P0, P1
   uint8_t length;       // 1 to 8 bytes
   uint8_t data[LIN_MAX_DATA_BYTES];
   uint8_t checksum;
   bool isEnhancedChecksum;
} LinFrame;

typedef struct LinScheduleEntry
{
   uint8_t frameId;
   uint32_t slotDurationMs;
} LinScheduleEntry;

typedef struct LinMasterScheduler
{
   uint32_t channelId;
   LinScheduleEntry schedule[LIN_MAX_SCHEDULE_ENTRIES];
   uint32_t scheduleCount;
   uint32_t currentSlotIndex;
   uint64_t lastSlotAdvanceMs;
   uint64_t totalFramesSent;
   uint64_t checksumErrors;
} LinMasterScheduler;

uint8_t lin_compute_pid(uint8_t frameId);
bool lin_verify_pid(uint8_t pid);
uint8_t lin_compute_checksum(uint8_t pid, const uint8_t* data, uint8_t length, bool isEnhanced);
void lin_scheduler_init(LinMasterScheduler* sched, uint32_t channelId);
bool lin_scheduler_add_slot(LinMasterScheduler* sched, uint8_t frameId, uint32_t slotDurationMs);
bool lin_scheduler_tick(LinMasterScheduler* sched, uint64_t currentMs, uint8_t* outFrameId);

#endif // MANIFOLD_CAN_EH
