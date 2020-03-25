// runtime/ec_runtime.c
// Implementation of eC runtime core memory and container primitives.

#include "ec_runtime.h"

void* ec_runtime_alloc(size_t bytes)
{
   void* ptr = calloc(1, bytes);
   if(!ptr && bytes > 0)
   {
      fprintf(stderr, "FATAL: Out of memory allocating %zu bytes\n", bytes);
      abort();
   }
   return ptr;
}

void* ec_runtime_realloc(void* ptr, size_t bytes)
{
   void* newPtr = realloc(ptr, bytes);
   if(!newPtr && bytes > 0)
   {
      fprintf(stderr, "FATAL: Out of memory reallocating %zu bytes\n", bytes);
      abort();
   }
   return newPtr;
}

EcBuffer* ec_buffer_create(size_t initialCapacity)
{
   EcBuffer* buf = EC_NEW(EcBuffer);
   buf->capacity = (initialCapacity > 0) ? initialCapacity : 64;
   buf->data = (uint8_t*)ec_runtime_alloc(buf->capacity);
   buf->size = 0;
   return buf;
}

void ec_buffer_destroy(EcBuffer* buf)
{
   if(!buf) return;
   EC_FREE(buf->data);
   EC_FREE(buf);
}

bool ec_buffer_append(EcBuffer* buf, const uint8_t* src, size_t len)
{
   if(!buf || !src || len == 0) return false;
   if(buf->size + len > buf->capacity)
   {
      size_t newCap = (buf->capacity * 2 > buf->size + len) ? buf->capacity * 2 : buf->size + len + 64;
      buf->data = (uint8_t*)ec_runtime_realloc(buf->data, newCap);
      buf->capacity = newCap;
   }
   memcpy(buf->data + buf->size, src, len);
   buf->size += len;
   return true;
}

bool ec_buffer_append_byte(EcBuffer* buf, uint8_t byte)
{
   return ec_buffer_append(buf, &byte, 1);
}

void ec_buffer_clear(EcBuffer* buf)
{
   if(buf) buf->size = 0;
}

EcArray* ec_array_create(size_t initialCapacity)
{
   EcArray* arr = EC_NEW(EcArray);
   arr->capacity = (initialCapacity > 0) ? initialCapacity : 16;
   arr->items = (void**)ec_runtime_alloc(sizeof(void*) * arr->capacity);
   arr->count = 0;
   return arr;
}

void ec_array_destroy(EcArray* arr, void (*itemFree)(void*))
{
   if(!arr) return;
   if(itemFree)
   {
      for(size_t i = 0; i < arr->count; i++)
      {
         if(arr->items[i]) itemFree(arr->items[i]);
      }
   }
   EC_FREE(arr->items);
   EC_FREE(arr);
}

bool ec_array_add(EcArray* arr, void* item)
{
   if(!arr) return false;
   if(arr->count >= arr->capacity)
   {
      size_t newCap = arr->capacity * 2;
      arr->items = (void**)ec_runtime_realloc(arr->items, sizeof(void*) * newCap);
      arr->capacity = newCap;
   }
   arr->items[arr->count++] = item;
   return true;
}

void* ec_array_get(const EcArray* arr, size_t index)
{
   if(!arr || index >= arr->count) return NULL;
   return arr->items[index];
}

bool ec_array_set(EcArray* arr, size_t index, void* item)
{
   if(!arr || index >= arr->count) return false;
   arr->items[index] = item;
   return true;
}

void ec_array_clear(EcArray* arr, void (*itemFree)(void*))
{
   if(!arr) return;
   if(itemFree)
   {
      for(size_t i = 0; i < arr->count; i++)
      {
         if(arr->items[i]) itemFree(arr->items[i]);
      }
   }
   arr->count = 0;
}

static size_t hash_string(const char* str, size_t bucketCount)
{
   size_t hash = 5381;
   int c;
   while((c = *str++))
      hash = ((hash << 5) + hash) + (size_t)c;
   return hash % bucketCount;
}

EcMap* ec_map_create(size_t bucketCount)
{
   EcMap* map = EC_NEW(EcMap);
   map->bucketCount = (bucketCount > 0) ? bucketCount : 31;
   map->buckets = (EcMapEntry**)ec_runtime_alloc(sizeof(EcMapEntry*) * map->bucketCount);
   map->count = 0;
   return map;
}

void ec_map_destroy(EcMap* map, void (*valFree)(void*))
{
   if(!map) return;
   for(size_t i = 0; i < map->bucketCount; i++)
   {
      EcMapEntry* entry = map->buckets[i];
      while(entry)
      {
         EcMapEntry* next = entry->next;
         EC_FREE(entry->key);
         if(valFree && entry->value) valFree(entry->value);
         EC_FREE(entry);
         entry = next;
      }
   }
   EC_FREE(map->buckets);
   EC_FREE(map);
}

bool ec_map_put(EcMap* map, const char* key, void* value)
{
   if(!map || !key) return false;
   size_t idx = hash_string(key, map->bucketCount);
   EcMapEntry* entry = map->buckets[idx];
   while(entry)
   {
      if(strcmp(entry->key, key) == 0)
      {
         entry->value = value;
         return true;
      }
      entry = entry->next;
   }

   EcMapEntry* newEntry = EC_NEW(EcMapEntry);
   size_t klen = strlen(key);
   newEntry->key = (char*)ec_runtime_alloc(klen + 1);
   memcpy(newEntry->key, key, klen + 1);
   newEntry->value = value;
   newEntry->next = map->buckets[idx];
   map->buckets[idx] = newEntry;
   map->count++;
   return true;
}

void* ec_map_get(const EcMap* map, const char* key)
{
   if(!map || !key) return NULL;
   size_t idx = hash_string(key, map->bucketCount);
   EcMapEntry* entry = map->buckets[idx];
   while(entry)
   {
      if(strcmp(entry->key, key) == 0) return entry->value;
      entry = entry->next;
   }
   return NULL;
}

bool ec_map_remove(EcMap* map, const char* key, void (*valFree)(void*))
{
   if(!map || !key) return false;
   size_t idx = hash_string(key, map->bucketCount);
   EcMapEntry* prev = NULL;
   EcMapEntry* entry = map->buckets[idx];
   while(entry)
   {
      if(strcmp(entry->key, key) == 0)
      {
         if(prev) prev->next = entry->next;
         else map->buckets[idx] = entry->next;

         EC_FREE(entry->key);
         if(valFree && entry->value) valFree(entry->value);
         EC_FREE(entry);
         map->count--;
         return true;
      }
      prev = entry;
      entry = entry->next;
   }
   return false;
}

uint64_t ec_get_time_us(void)
{
#if defined(__APPLE__) || defined(__linux__)
   struct timeval tv;
   gettimeofday(&tv, NULL);
   return ((uint64_t)tv.tv_sec * 1000000ULL) + (uint64_t)tv.tv_usec;
#else
   return (uint64_t)clock() * (1000000ULL / CLOCKS_PER_SEC);
#endif
}

uint64_t ec_get_time_ms(void)
{
   return ec_get_time_us() / 1000ULL;
}
