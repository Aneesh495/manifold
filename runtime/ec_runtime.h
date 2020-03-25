// runtime/ec_runtime.h
// Core runtime support and container libraries for eC programs.
// Provides zero-dependency memory management, dynamic arrays, and string utilities.

#ifndef EC_RUNTIME_H
#define EC_RUNTIME_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <time.h>

#if defined(__APPLE__) || defined(__linux__)
#include <sys/time.h>
#include <pthread.h>
#endif

// PrintLn macro matching eC standard library behavior
#define PrintLn(...) do { \
   printf(__VA_ARGS__); \
   printf("\n"); \
   fflush(stdout); \
} while(0)

// Safe allocation macros
#define EC_NEW(T) ((T*)ec_runtime_alloc(sizeof(T)))
#define EC_NEW_ARRAY(T, count) ((T*)ec_runtime_alloc(sizeof(T) * (count)))
#define EC_FREE(ptr) do { if(ptr) { free(ptr); ptr = NULL; } } while(0)

// Dynamic Byte Buffer
typedef struct EcBuffer
{
   uint8_t* data;
   size_t size;
   size_t capacity;
} EcBuffer;

// Dynamic generic Array container
typedef struct EcArray
{
   void** items;
   size_t count;
   size_t capacity;
} EcArray;

// Dynamic Key-Value Map container
typedef struct EcMapEntry
{
   char* key;
   void* value;
   struct EcMapEntry* next;
} EcMapEntry;

typedef struct EcMap
{
   EcMapEntry** buckets;
   size_t bucketCount;
   size_t count;
} EcMap;

// Runtime lifecycle and memory primitives
void* ec_runtime_alloc(size_t bytes);
void* ec_runtime_realloc(void* ptr, size_t bytes);

// Buffer operations
EcBuffer* ec_buffer_create(size_t initialCapacity);
void ec_buffer_destroy(EcBuffer* buf);
bool ec_buffer_append(EcBuffer* buf, const uint8_t* src, size_t len);
bool ec_buffer_append_byte(EcBuffer* buf, uint8_t byte);
void ec_buffer_clear(EcBuffer* buf);

// Array operations
EcArray* ec_array_create(size_t initialCapacity);
void ec_array_destroy(EcArray* arr, void (*itemFree)(void*));
bool ec_array_add(EcArray* arr, void* item);
void* ec_array_get(const EcArray* arr, size_t index);
bool ec_array_set(EcArray* arr, size_t index, void* item);
void ec_array_clear(EcArray* arr, void (*itemFree)(void*));

// Map operations
EcMap* ec_map_create(size_t bucketCount);
void ec_map_destroy(EcMap* map, void (*valFree)(void*));
bool ec_map_put(EcMap* map, const char* key, void* value);
void* ec_map_get(const EcMap* map, const char* key);
bool ec_map_remove(EcMap* map, const char* key, void (*valFree)(void*));

// Time utilities
uint64_t ec_get_time_us(void);
uint64_t ec_get_time_ms(void);

// Endianness converters
static inline uint16_t ec_swap16(uint16_t val)
{
   return (uint16_t)((val << 8) | (val >> 8));
}

static inline uint32_t ec_swap32(uint32_t val)
{
   return ((val << 24) & 0xFF000000U) |
          ((val <<  8) & 0x00FF0000U) |
          ((val >>  8) & 0x0000FF00U) |
          ((val >> 24) & 0x000000FFU);
}

static inline uint64_t ec_swap64(uint64_t val)
{
   return ((val & 0x00000000000000FFULL) << 56) |
          ((val & 0x000000000000FF00ULL) << 40) |
          ((val & 0x0000000000FF0000ULL) << 24) |
          ((val & 0x00000000FF000000ULL) <<  8) |
          ((val & 0x000000FF00000000ULL) >>  8) |
          ((val & 0x0000FF0000000000ULL) >> 24) |
          ((val & 0x00FF000000000000ULL) >> 40) |
          ((val & 0xFF00000000000000ULL) >> 56);
}

#endif // EC_RUNTIME_H
