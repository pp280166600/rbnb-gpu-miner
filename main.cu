#include <cuda.h>
#include <cuda_runtime.h>
#include <curand_kernel.h>
#include <stdint.h>
#include <stdio.h>
#include <io.h>
#include <process.h>
#include "common.cuh"
#include "getopt.cuh"
#include "sha3.cuh"

#define BLOCKS 32
#define THREADS 256

#define N 1000000
struct Result
{
    char id[65];
};

__device__ uint8_t dev_wanted_signature[4] = {0x0, 0x0, 0x0, 0x0};
__device__ uint8_t dev_wanted_signature2[3] = {0x99, 0x99, 0x99};

__global__ void init_signature(uint32_t *fn_sig)
{
    dev_wanted_signature[0] = *fn_sig >> 24;
    dev_wanted_signature[1] = ((*fn_sig >> 16) & 0xff);
    dev_wanted_signature[2] = ((*fn_sig >> 8) & 0xff);
    dev_wanted_signature[3] = ((*fn_sig >> 0) & 0xff);
}

__host__ __device__ unsigned char hex_char_to_char(char c)
{
    if (c >= '0' && c <= '9')
    {
        return (unsigned char)(c - '0');
    }
    else if (c >= 'a' && c <= 'f')
    {
        return (unsigned char)(c - 'a' + 10);
    }
    else if (c >= 'A' && c <= 'F')
    {
        return (unsigned char)(c - 'A' + 10);
    }
    else
    {
        return 0;
    }
}

// 将十六进制字符串转换为字节数组
__host__ __device__ void hex_string_to_char_array(char hex_string[], unsigned char char_array[])
{
    size_t len = _strlen(hex_string);
    size_t byte_len = len / 2;

    for (size_t i = 0; i < byte_len; ++i)
    {
        char_array[i] = (hex_char_to_char(hex_string[i * 2]) << 4) | hex_char_to_char(hex_string[i * 2 + 1]);
    }
}

// 避免内存重叠版的memcpy
__device__ void *_memcpy(void *dst, const void *src, unsigned int count)
{
    void *ret = dst;
    if (dst <= src || (char *)dst >= ((char *)src + count)) //
    {
        while (count--)
        {
            *(char *)dst = *(char *)src;
            dst = (char *)dst + 1;
            src = (char *)src + 1;
        }
    }
    else
    {
        dst = (char *)dst + count - 1;
        src = (char *)src + count - 1;
        while (count--)
        {
            *(char *)dst = *(char *)src;
            dst = (char *)dst - 1;
            src = (char *)src - 1;
        }
    }
    return ret;
}

__global__ void calculate(char *address, char *challenge_value, Result *results)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    curandState state;
    curand_init((unsigned long long)clock64() + tid, tid, 0, &state);
    char id[65];
    char res[193];
    char challenge_hex[] = "72424e4200000000000000000000000000000000000000000000000000000000000000000000000000000000";
    const size_t len = 96;
    unsigned char data[len];
    char hex_array[] = {'0', '1', '2', '3', '4', '5', '6', '7',
                        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
    for (int i = 0; i < N; i++)
    {
        uint8_t hash[64];
        memset(id, 0, 64);
        for (int k = 0; k < 64; k++)
        {
            int block = (curand(&state) % 16);
            id[k] = hex_array[block];
        }
        memset(data, 0, len);
        memset(res, 0, 193);
        id[64] = '\0';
        _memcpy(&res, id, _strlen(id));
        _memcpy(&res[_strlen(res)], challenge_hex, _strlen(challenge_hex));
        _memcpy(&res[_strlen(res)], address, _strlen(address));
        hex_string_to_char_array(res, data);
        sha3_return_t ok = sha3_HashBuffer(256, SHA3_FLAGS_KECCAK, data,
                                           len, hash, 64);
        if (ok != 0)
        {
            printf("bad params\n");
            return;
        }
        if (hash[0] == dev_wanted_signature2[0] &&
            hash[1] == dev_wanted_signature2[1] &&
            hash[2] == dev_wanted_signature2[2])
        {
            _memcpy(&results[tid].id, id, _strlen(id));
            printf("Tid: %d  Hex: %s\n", tid, id);
            return;
        }
    }
}

int main(int argc, char **argv)
{
    int opt;
    char *avalue = NULL; // 
    char *mvalue = NULL; // 
    while ((opt = getopt(argc, argv, "a:m:")) != -1)
    {
        switch (opt)
        {
        case 'm':
            mvalue = optarg;
            break;
        case 'a':
            avalue = optarg;
            break;
        default: /* '?' */
            usage(argv[0]);
            exit(EXIT_FAILURE);
        }
    }

    if (mvalue == NULL || avalue == NULL)
    {
        usage(argv[0]);
        exit(EXIT_FAILURE);
    }
    const char *filename = "result.txt";
    FILE *file = fopen(filename, "r+");
    if (file == NULL)
    {
        file = fopen(filename, "w+");
    }
    fseek(file, 0, SEEK_END);

    char *dev_m, *dev_a;
    Result *host_results = (Result *)malloc(BLOCKS * THREADS * sizeof(Result));
    Result *device_data;
    HANDLE_ERROR(cudaMalloc((void **)&device_data, BLOCKS * THREADS * sizeof(Result)));
    HANDLE_ERROR(cudaMalloc((void **)&dev_m, _strlen(mvalue) * sizeof(char)));
    HANDLE_ERROR(cudaMalloc((void **)&dev_a, _strlen(avalue) * sizeof(char)));
    HANDLE_ERROR(cudaMemcpy(dev_m, mvalue, _strlen(mvalue) * sizeof(char),
                            cudaMemcpyHostToDevice));
    HANDLE_ERROR(cudaMemcpy(dev_a, avalue, _strlen(avalue) * sizeof(char),
                            cudaMemcpyHostToDevice));
    calculate<<<BLOCKS, THREADS>>>(dev_a, dev_m, (Result *)device_data);
    cudaDeviceSynchronize(); // not important
    HANDLE_ERROR(cudaMemcpy(host_results, device_data, (BLOCKS * THREADS * sizeof(Result)), cudaMemcpyDeviceToHost));
    for (int i = 0; i < BLOCKS * THREADS; i++)
    {

        if (_strlen(host_results[i].id) > 0)
        {
            fprintf(file, "0x%s,0x%s\n", host_results[i].id, avalue);
        }
    }
    HANDLE_ERROR(cudaFree(dev_m));
    HANDLE_ERROR(cudaFree(dev_a));
    HANDLE_ERROR(cudaFree(device_data));
    free(host_results);
    printf("success all, result for result.txt\n");
    exit(EXIT_SUCCESS);
}
