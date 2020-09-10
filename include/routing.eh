// include/routing.eh
// In-Vehicle Central Gateway routing rules and traffic shaping definitions.

#ifndef MANIFOLD_ROUTING_EH
#define MANIFOLD_ROUTING_EH

#include <stdint.h>
#include <stdbool.h>

#include "types.eh"
#include "can.eh"
#include "someip.eh"

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

// Token Bucket Traffic Shaper
typedef struct TokenBucket
{
   uint32_t capacity;
   uint32_t currentTokens;
   uint32_t refillRatePerSec;
   uint64_t lastRefillMs;
} TokenBucket;

#define EGRESS_QUEUE_CAPACITY 64

typedef struct EgressQueueItem
{
   CanFrame frame;
   uint8_t priority;
} EgressQueueItem;

typedef struct EgressQueue
{
   EgressQueueItem items[EGRESS_QUEUE_CAPACITY];
   uint32_t head;
   uint32_t tail;
   uint32_t count;
} EgressQueue;

// Bridge definitions
typedef struct CanSomeipBridge
{
   uint32_t canId;
   uint16_t serviceId;
   uint16_t methodOrEventId;
   uint8_t interfaceVersion;
} CanSomeipBridge;

// Function Prototypes

// Routing Table (RoutingTable.ec)
void routing_table_init(RoutingTable* table);
bool routing_table_add_rule(RoutingTable* table, BusDomain srcDomain, uint32_t srcId, uint32_t mask, BusDomain dstDomain, uint32_t dstId, RouteAction action, uint32_t priority);
const RouteRule* routing_table_match(const RoutingTable* table, BusDomain srcDomain, uint32_t canId);
bool routing_table_route_frame(const RoutingTable* table, BusDomain srcDomain, const CanFrame* inFrame, BusDomain* outDomain, CanFrame* outFrame);

// Traffic Shaping (TrafficShaper.ec)
void traffic_shaper_init(TokenBucket* bucket, uint32_t capacity, uint32_t refillRatePerSec);
bool traffic_shaper_consume(TokenBucket* bucket, uint32_t tokens, uint64_t currentMs);
void egress_queue_init(EgressQueue* q);
bool egress_queue_push(EgressQueue* q, const CanFrame* frame, uint8_t priority);
bool egress_queue_pop(EgressQueue* q, CanFrame* outFrame);

// Cross-Domain Bridge (BridgeCanSomeip.ec)
void bridge_init(CanSomeipBridge* bridge, uint32_t canId, uint16_t serviceId, uint16_t methodOrEventId, uint8_t interfaceVer);
bool bridge_can_to_someip(const CanSomeipBridge* bridge, const CanFrame* frame, SomeIpMessage* outSomeip);
bool bridge_someip_to_can(const CanSomeipBridge* bridge, const SomeIpMessage* msg, CanFrame* outFrame);

#endif // MANIFOLD_ROUTING_EH
