// include/routing.eh
// In-Vehicle Central Gateway routing rules and traffic shaping definitions.

#ifndef MANIFOLD_ROUTING_EH
#define MANIFOLD_ROUTING_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"
#include "can.eh"

typedef enum BusDomain
{
   BUS_DOMAIN_POWERTRAIN = 0, // CAN FD 5 Mbps
   BUS_DOMAIN_CHASSIS    = 1, // CAN FD 5 Mbps
   BUS_DOMAIN_BODY       = 2, // CAN 2.0B 500 kbps
   BUS_DOMAIN_LIN_DOORS  = 3, // LIN 2.2 19.2 kbps
   BUS_DOMAIN_ETHERNET   = 4, // SOME/IP 1000BASE-T1
   BUS_DOMAIN_DIAGNOSTIC = 5  // DoIP / OBD-II
} BusDomain;

typedef enum RouteAction
{
   ROUTE_ACTION_FORWARD        = 0,
   ROUTE_ACTION_TRANSLATE_ID   = 1,
   ROUTE_ACTION_REPACKAGE_PDU  = 2,
   ROUTE_ACTION_DROP           = 3
} RouteAction;

typedef struct RouteRule
{
   BusDomain sourceDomain;
   uint32_t sourceId;
   uint32_t mask;
   BusDomain destDomain;
   uint32_t destId;
   RouteAction action;
   uint32_t priority;
} RouteRule;

#define MAX_ROUTING_RULES 128

typedef struct RoutingTable
{
   RouteRule rules[MAX_ROUTING_RULES];
   uint32_t ruleCount;
} RoutingTable;

#endif // MANIFOLD_ROUTING_EH
