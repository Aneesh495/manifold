// src/routing/RoutingTable.ec
// Central Gateway multi-bus routing table with bitmask filtering and priority arbitration.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "types.eh"
#include "can.eh"
#include "routing.eh"
#include "ec_runtime.h"

// Initializes a gateway routing table
void routing_table_init(RoutingTable* table)
{
   if(!table) return;
   memset(table, 0, sizeof(RoutingTable));
}

// Registers a routing rule with source domain, bitmask match, egress destination, and priority
bool routing_table_add_rule(RoutingTable* table, BusDomain srcDomain, uint32_t srcId, uint32_t mask, BusDomain dstDomain, uint32_t dstId, RouteAction action, uint32_t priority)
{
   if(!table || table->ruleCount >= MAX_ROUTING_RULES)
   {
      return false;
   }

   RouteRule* r = &table->rules[table->ruleCount++];
   r->sourceDomain = srcDomain;
   r->sourceId     = srcId;
   r->mask         = mask;
   r->destDomain   = dstDomain;
   r->destId       = dstId;
   r->action       = action;
   r->priority     = priority;

   return true;
}

// Matches an incoming frame against the routing table, choosing the highest priority rule
const RouteRule* routing_table_match(const RoutingTable* table, BusDomain srcDomain, uint32_t canId)
{
   if(!table) return NULL;

   const RouteRule* bestMatch = NULL;
   uint32_t highestPriority = 0;

   for(uint32_t i = 0; i < table->ruleCount; i++)
   {
      const RouteRule* r = &table->rules[i];
      if(r->sourceDomain == srcDomain)
      {
         if((canId & r->mask) == (r->sourceId & r->mask))
         {
            if(!bestMatch || r->priority > highestPriority)
            {
               bestMatch = r;
               highestPriority = r->priority;
            }
         }
      }
   }

   return bestMatch;
}

// Applies routing rules to an ingress CAN frame, performing translation or forwarding
bool routing_table_route_frame(const RoutingTable* table, BusDomain srcDomain, const CanFrame* inFrame, BusDomain* outDomain, CanFrame* outFrame)
{
   if(!table || !inFrame || !outDomain || !outFrame)
   {
      return false;
   }

   const RouteRule* rule = routing_table_match(table, srcDomain, inFrame->arbitrationId);
   if(!rule || rule->action == ROUTE_ACTION_DROP)
   {
      return false;
   }

   *outDomain = rule->destDomain;
   *outFrame  = *inFrame;

   if(rule->action == ROUTE_ACTION_TRANSLATE_ID)
   {
      outFrame->arbitrationId = rule->destId;
   }

   return true;
}
