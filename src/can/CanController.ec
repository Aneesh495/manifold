// src/can/CanController.ec
// CAN and CAN FD hardware controller mailbox state machine and error handling.
// Simulates hardware message RAM, acceptance filters, TEC/REC error counters, and bus-off recovery.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "ec_runtime.h"

void can_controller_init(CanController* ctrl, uint32_t id)
{
   if(!ctrl) return;
   memset(ctrl, 0, sizeof(CanController));
   ctrl->controllerId = id;
   ctrl->state = CAN_STATE_ERROR_ACTIVE;
}

bool can_controller_add_filter(CanController* ctrl, uint32_t filterId, uint32_t filterMask, bool isExtended)
{
   if(!ctrl) return false;
   for(int i = 0; i < CAN_CONTROLLER_MAX_FILTERS; i++)
   {
      if(!ctrl->filters[i].isActive)
      {
         ctrl->filters[i].isActive = true;
         ctrl->filters[i].isExtended = isExtended;
         ctrl->filters[i].filterId = isExtended ? (filterId & 0x1FFFFFFF) : (filterId & 0x7FF);
         ctrl->filters[i].filterMask = isExtended ? (filterMask & 0x1FFFFFFF) : (filterMask & 0x7FF);
         return true;
      }
   }
   return false;
}

bool can_controller_matches_filter(const CanController* ctrl, const CanFrame* frame)
{
   if(!ctrl || !frame) return false;

   bool anyFilter = false;
   for(int i = 0; i < CAN_CONTROLLER_MAX_FILTERS; i++)
   {
      if(ctrl->filters[i].isActive)
      {
         anyFilter = true;
         if(ctrl->filters[i].isExtended == (frame->flags.isExtended != 0))
         {
            if((frame->arbitrationId & ctrl->filters[i].filterMask) ==
               (ctrl->filters[i].filterId & ctrl->filters[i].filterMask))
            {
               return true;
            }
         }
      }
   }
   return !anyFilter;
}

bool can_controller_send_frame(CanController* ctrl, const CanFrame* frame)
{
   if(!ctrl || !frame || ctrl->state == CAN_STATE_BUS_OFF) return false;

   for(int i = 0; i < CAN_CONTROLLER_MAX_MAILBOXES; i++)
   {
      if(ctrl->mailboxes[i].type == MAILBOX_TYPE_TX && !ctrl->mailboxes[i].isPending)
      {
         ctrl->mailboxes[i].frame = *frame;
         ctrl->mailboxes[i].isPending = true;
         ctrl->totalTransmitted++;

         if(ctrl->tec > 0) ctrl->tec--;
         return true;
      }
   }
   return false;
}

bool can_controller_receive_frame(CanController* ctrl, const CanFrame* frame)
{
   if(!ctrl || !frame || ctrl->state == CAN_STATE_BUS_OFF) return false;

   if(!can_controller_matches_filter(ctrl, frame))
   {
      return false;
   }

   for(int i = 0; i < CAN_CONTROLLER_MAX_MAILBOXES; i++)
   {
      if(ctrl->mailboxes[i].type == MAILBOX_TYPE_RX && !ctrl->mailboxes[i].isPending)
      {
         ctrl->mailboxes[i].frame = *frame;
         ctrl->mailboxes[i].isPending = true;
         ctrl->totalReceived++;

         if(ctrl->rec > 0) ctrl->rec--;
         return true;
      }
   }
   return false;
}

void can_controller_record_tx_error(CanController* ctrl)
{
   if(!ctrl || ctrl->state == CAN_STATE_BUS_OFF) return;

   ctrl->errorFrames++;
   ctrl->tec += 8;

   if(ctrl->tec >= 256)
   {
      ctrl->state = CAN_STATE_BUS_OFF;
      ctrl->busOffCount++;
      ctrl->busOffRecoveryCounter = 0;
   }
   else if(ctrl->tec >= 128)
   {
      ctrl->state = CAN_STATE_ERROR_PASSIVE;
   }
}

void can_controller_record_rx_error(CanController* ctrl)
{
   if(!ctrl || ctrl->state == CAN_STATE_BUS_OFF) return;

   ctrl->errorFrames++;
   ctrl->rec++;

   if(ctrl->rec >= 128 && ctrl->state == CAN_STATE_ERROR_ACTIVE)
   {
      ctrl->state = CAN_STATE_ERROR_PASSIVE;
   }
}

bool can_controller_recover_bus_off(CanController* ctrl)
{
   if(!ctrl || ctrl->state != CAN_STATE_BUS_OFF) return false;

   ctrl->busOffRecoveryCounter++;
   if(ctrl->busOffRecoveryCounter >= 128)
   {
      ctrl->state = CAN_STATE_ERROR_ACTIVE;
      ctrl->tec = 0;
      ctrl->rec = 0;
      ctrl->busOffRecoveryCounter = 0;
      return true;
   }
   return false;
}
