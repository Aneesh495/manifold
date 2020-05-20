// src/uds/UdsPdu.ec
// ISO 14229-1 Protocol Data Unit (PDU) framing, negative response generation,
// and suppressPositiveResponse handling.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "uds.eh"
#include "ec_runtime.h"

#define UDS_SUPPRESS_POS_RSP_MASK 0x80

// Builds an ISO 14229 Negative Response message: 0x7F <SID> <NRC>
uint32_t uds_build_negative_response(uint8_t rejectedSid, NegativeResponseCode nrc, uint8_t* outResp, uint32_t maxRespLen)
{
   if(!outResp || maxRespLen < 3) return 0;

   outResp[0] = UDS_SID_NEGATIVE_RESPONSE; // 0x7F
   outResp[1] = rejectedSid;
   outResp[2] = (uint8_t)nrc;
   return 3;
}

// Checks if the suppressPositiveResponse bit (bit 7) is set in the subfunction
bool uds_is_suppress_pos_rsp(uint8_t subfunction)
{
   return (subfunction & UDS_SUPPRESS_POS_RSP_MASK) != 0;
}

// Extracts clean subfunction code without the suppressPositiveResponse bit
uint8_t uds_get_clean_subfunction(uint8_t subfunction)
{
   return subfunction & ~UDS_SUPPRESS_POS_RSP_MASK;
}
