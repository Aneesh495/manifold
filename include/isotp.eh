// include/isotp.eh
// ISO 15765-2 (ISO-TP) Transport Layer Protocol definitions.

#ifndef MANIFOLD_ISOTP_EH
#define MANIFOLD_ISOTP_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"
#include "can.eh"

// ISO-TP Protocol Control Information (N_PCI) Frame Types
typedef enum IsoTpFrameType
{
   ISOTP_FRAME_SINGLE = 0x00,
   ISOTP_FRAME_FIRST = 0x01,
   ISOTP_FRAME_CONSECUTIVE = 0x02,
   ISOTP_FRAME_FLOW_CONTROL = 0x03
} IsoTpFrameType;

// Flow Control Flow Status (FS)
typedef enum IsoTpFlowStatus
{
   ISOTP_FS_CTS = 0x00,      // Clear To Send
   ISOTP_FS_WAIT = 0x01,     // Wait
   ISOTP_FS_OVERFLOW = 0x02  // Overflow / Abort
} IsoTpFlowStatus;

// ISO-TP Session State
typedef enum IsoTpState
{
   ISOTP_STATE_IDLE = 0,
   ISOTP_STATE_SENDING = 1,
   ISOTP_STATE_WAIT_FC = 2,
   ISOTP_STATE_RECEIVING = 3,
   ISOTP_STATE_ERROR = 4
} IsoTpState;

// ISO-TP Config parameters
typedef struct IsoTpConfig
{
   uint32_t rxId;
   uint32_t txId;
   bool isExtended;
   bool isFd;
   uint8_t blockSize;       // BS: 0 means no limit
   uint8_t separationTime;  // STmin: milliseconds or microseconds
   uint32_t timeoutAs;      // Transmit timeout
   uint32_t timeoutBs;      // Wait for Flow Control timeout
   uint32_t timeoutCr;      // Wait for Consecutive Frame timeout
} IsoTpConfig;

// Maximum message buffer for multi-frame diagnostics (up to 64 KB or 4 GB in ISO 15765-2:2016)
#define ISOTP_MAX_MSG_SIZE 65536

// ISO-TP Channel structure
typedef struct IsoTpChannel
{
   IsoTpConfig config;
   IsoTpState state;
   uint8_t rxBuffer[ISOTP_MAX_MSG_SIZE];
   uint32_t rxExpectedLen;
   uint32_t rxReceivedLen;
   uint8_t rxSequenceNumber;
   uint8_t rxBlockCounter;

   uint8_t txBuffer[ISOTP_MAX_MSG_SIZE];
   uint32_t txTotalLen;
   uint32_t txSentLen;
   uint8_t txSequenceNumber;
   uint8_t txBlockSize;
   uint8_t txSeparationTime;

   Timestamp lastActivityTime;
} IsoTpChannel;

void isotp_channel_init(IsoTpChannel* chan, const IsoTpConfig* config);
bool isotp_transmit(IsoTpChannel* chan, const uint8_t* payload, uint32_t length);
bool isotp_receive_can_frame(IsoTpChannel* chan, const CanFrame* frame, uint8_t* outMsg, uint32_t* outLen);
bool isotp_poll_transmit(IsoTpChannel* chan, CanFrame* outFrame, bool* frameReady);

#endif // MANIFOLD_ISOTP_EH
