// c_fastpath/aes128_cmac.c
// RFC 4493 / NIST SP 800-38B AES-128 CMAC implementation for AUTOSAR SecOC fastpath acceleration.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

// Forward declarations
void aes128_encrypt_block(const uint8_t* key, const uint8_t* in, uint8_t* out);
void aes128_cmac(const uint8_t* key, const uint8_t* msg, uint32_t len, uint8_t* mac);

// AES S-box
static const uint8_t sbox[256] = {
   0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
   0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
   0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
   0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
   0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
   0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
   0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
   0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
   0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
   0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
   0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
   0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
   0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
   0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
   0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
   0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
};

// Round constants
static const uint8_t rcon[10] = { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36 };

// Key expansion for AES-128
static void aes128_key_expansion(const uint8_t* key, uint8_t* w)
{
   memcpy(w, key, 16);
   for(int i = 4; i < 44; i++)
   {
      uint8_t temp[4];
      memcpy(temp, &w[(i - 1) * 4], 4);
      if(i % 4 == 0)
      {
         // RotWord
         uint8_t k = temp[0];
         temp[0] = temp[1];
         temp[1] = temp[2];
         temp[2] = temp[3];
         temp[3] = k;
         // SubWord
         temp[0] = sbox[temp[0]];
         temp[1] = sbox[temp[1]];
         temp[2] = sbox[temp[2]];
         temp[3] = sbox[temp[3]];
         // Rcon
         temp[0] ^= rcon[(i / 4) - 1];
      }
      w[i * 4 + 0] = w[(i - 4) * 4 + 0] ^ temp[0];
      w[i * 4 + 1] = w[(i - 4) * 4 + 1] ^ temp[1];
      w[i * 4 + 2] = w[(i - 4) * 4 + 2] ^ temp[2];
      w[i * 4 + 3] = w[(i - 4) * 4 + 3] ^ temp[3];
   }
}

static uint8_t gmul(uint8_t a, uint8_t b)
{
   uint8_t p = 0;
   while(a && b)
   {
      if(b & 1) p ^= a;
      if(a & 0x80) a = (uint8_t)((a << 1) ^ 0x1b);
      else a <<= 1;
      b >>= 1;
   }
   return p;
}

// Encrypts single 16-byte block with AES-128
void aes128_encrypt_block(const uint8_t* key, const uint8_t* in, uint8_t* out)
{
   uint8_t w[176];
   aes128_key_expansion(key, w);

   uint8_t state[16];
   for(int i = 0; i < 16; i++) state[i] = in[i] ^ w[i];

   for(int round = 1; round <= 10; round++)
   {
      // SubBytes
      for(int i = 0; i < 16; i++) state[i] = sbox[state[i]];

      // ShiftRows
      uint8_t t[16];
      t[0] = state[0];   t[1] = state[5];   t[2] = state[10];  t[3] = state[15];
      t[4] = state[4];   t[5] = state[9];   t[6] = state[14];  t[7] = state[3];
      t[8] = state[8];   t[9] = state[13];  t[10] = state[2];  t[11] = state[7];
      t[12] = state[12]; t[13] = state[1];  t[14] = state[6];  t[15] = state[11];
      memcpy(state, t, 16);

      // MixColumns (rounds 1 to 9)
      if(round < 10)
      {
         for(int c = 0; c < 4; c++)
         {
            int idx = c * 4;
            uint8_t a = state[idx], b = state[idx + 1], c_val = state[idx + 2], d = state[idx + 3];
            state[idx]     = gmul(2, a) ^ gmul(3, b) ^ c_val ^ d;
            state[idx + 1] = a ^ gmul(2, b) ^ gmul(3, c_val) ^ d;
            state[idx + 2] = a ^ b ^ gmul(2, c_val) ^ gmul(3, d);
            state[idx + 3] = gmul(3, a) ^ b ^ c_val ^ gmul(2, d);
         }
      }

      // AddRoundKey
      for(int i = 0; i < 16; i++) state[i] ^= w[round * 16 + i];
   }

   memcpy(out, state, 16);
}

// Left shift 128-bit block by 1 bit
static void left_shift_128(const uint8_t* in, uint8_t* out)
{
   uint8_t overflow = 0;
   for(int i = 15; i >= 0; i--)
   {
      out[i] = (uint8_t)((in[i] << 1) | overflow);
      overflow = (in[i] & 0x80) ? 1 : 0;
   }
}

// Generate subkeys K1 and K2 for RFC 4493 CMAC
static void aes128_cmac_generate_subkeys(const uint8_t* key, uint8_t* k1, uint8_t* k2)
{
   uint8_t zero[16] = {0};
   uint8_t L[16];
   aes128_encrypt_block(key, zero, L);

   // Generate K1
   left_shift_128(L, k1);
   if(L[0] & 0x80)
   {
      k1[15] ^= 0x87;
   }

   // Generate K2
   left_shift_128(k1, k2);
   if(k1[0] & 0x80)
   {
      k2[15] ^= 0x87;
   }
}

// RFC 4493 AES-128 CMAC calculation
void aes128_cmac(const uint8_t* key, const uint8_t* msg, uint32_t len, uint8_t* mac)
{
   uint8_t k1[16], k2[16];
   aes128_cmac_generate_subkeys(key, k1, k2);

   uint32_t n = (len + 15) / 16;
   bool flag = (n > 0) && (len % 16 == 0);
   if(n == 0)
   {
      n = 1;
      flag = false;
   }

   uint8_t m_last[16] = {0};
   if(flag)
   {
      for(int i = 0; i < 16; i++)
      {
         m_last[i] = msg[(n - 1) * 16 + i] ^ k1[i];
      }
   }
   else
   {
      uint32_t remainder = len % 16;
      if(len > 0)
      {
         memcpy(m_last, msg + (n - 1) * 16, remainder);
      }
      m_last[remainder] = 0x80;
      for(int i = 0; i < 16; i++)
      {
         m_last[i] ^= k2[i];
      }
   }

   uint8_t x[16] = {0};
   uint8_t y[16];

   for(uint32_t i = 0; i < (n - 1); i++)
   {
      for(int j = 0; j < 16; j++)
      {
         y[j] = x[j] ^ msg[i * 16 + j];
      }
      aes128_encrypt_block(key, y, x);
   }

   for(int j = 0; j < 16; j++)
   {
      y[j] = x[j] ^ m_last[j];
   }
   aes128_encrypt_block(key, y, mac);
}
