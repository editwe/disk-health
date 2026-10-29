/*
 * HealthReader.c — reads NVMe SMART health log via Apple's NVMeSMARTLib plugin
 * and returns it as a JSON string, so the GUI layer stays simple.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>

#include "HealthReader.h"

static char g_json[4096];

static void json_escape(char *dst, size_t dstlen, const char *src, size_t srclen)
{
    size_t o = 0;
    for (size_t i = 0; i < srclen && o + 2 < dstlen; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c == '"' || c == '\\') {
            dst[o++] = '\\';
            dst[o++] = (char)c;
        } else if (c >= 0x20 && c < 0x7f) {
            dst[o++] = (char)c;
        } else if (c == 0) {
            break;
        }
    }
    dst[o] = '\0';
}

static void copy_trimmed(char *dst, size_t dstlen, const uint8_t *src, size_t srclen)
{
    size_t n = srclen;
    while (n > 0 && (src[n - 1] == ' ' || src[n - 1] == 0)) n--;
    size_t start = 0;
    while (start < n && src[start] == ' ') start++;
    if (n - start >= dstlen) n = start + dstlen - 1;
    memcpy(dst, src + start, n - start);
    dst[n - start] = '\0';
}

static void fill_error(int code, const char *msg)
{
    snprintf(g_json, sizeof(g_json),
             "{\"ok\":false,\"errorCode\":%d,\"error\":\"%s\"}", code, msg);
}

const char *dh_read_health_json(void)
{
    CFMutableDictionaryRef matching = IOServiceMatching("IOService");
    if (!matching) { fill_error(-1, "cannot create matching dictionary"); return g_json; }

    CFMutableDictionaryRef propmatch = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(propmatch, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFBooleanTrue);
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), propmatch);

    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != KERN_SUCCESS) {
        fill_error(-2, "IOServiceGetMatchingServices failed");
        return g_json;
    }

    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        IOCFPlugInInterface **plug = NULL;
        SInt32 score = 0;
        if (IOCreatePlugInInterfaceForService(svc, kIONVMeSMARTUserClientTypeID,
                                              kIOCFPlugInInterfaceID, &plug, &score) != KERN_SUCCESS || !plug) {
            IOObjectRelease(svc);
            continue;
        }

        IONVMeSMARTInterface **smart = NULL;
        CFUUIDBytes uuid = CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID);
        if ((*plug)->QueryInterface(plug, uuid, (LPVOID *)&smart) != S_OK || !smart) {
            (*plug)->Release(plug);
            IOObjectRelease(svc);
            continue;
        }

        NVMeSMARTData d;
        memset(&d, 0, sizeof(d));
        IOReturn r = (*smart)->SMARTReadData(smart, &d);
        if (r != kIOReturnSuccess) {
            (*smart)->Release(smart);
            (*plug)->Release(plug);
            IOObjectRelease(svc);
            continue;
        }

        char model[64] = "APPLE SSD", serial[32] = "", fw[16] = "";
        uint8_t *ident = calloc(1, 4096);
        if (ident) {
            if ((*smart)->GetIdentifyData(smart, ident, 0) == kIOReturnSuccess) {
                copy_trimmed(serial, sizeof(serial), ident + 4, 20);
                copy_trimmed(model, sizeof(model), ident + 24, 40);
                copy_trimmed(fw, sizeof(fw), ident + 64, 8);
            }
            free(ident);
        }

        char modelJ[160], serialJ[80], fwJ[48];
        json_escape(modelJ, sizeof(modelJ), model, strlen(model));
        json_escape(serialJ, sizeof(serialJ), serial, strlen(serial));
        json_escape(fwJ, sizeof(fwJ), fw, strlen(fw));

        unsigned long long written = d.DATA_UNITS_WRITTEN[0] * 512000ULL;
        unsigned long long read    = d.DATA_UNITS_READ[0] * 512000ULL;

        snprintf(g_json, sizeof(g_json),
            "{"
            "\"ok\":true,"
            "\"model\":\"%s\",\"serial\":\"%s\",\"firmware\":\"%s\","
            "\"criticalWarning\":%u,"
            "\"temperatureC\":%.1f,"
            "\"availableSpare\":%u,"
            "\"spareThreshold\":%u,"
            "\"percentageUsed\":%u,"
            "\"writtenBytes\":%llu,"
            "\"readBytes\":%llu,"
            "\"powerOnHours\":%llu,"
            "\"powerCycles\":%llu,"
            "\"unsafeShutdowns\":%llu,"
            "\"mediaErrors\":%llu,"
            "\"errorLogEntries\":%llu,"
            "\"hostWriteCommands\":%llu,"
            "\"hostReadCommands\":%llu"
            "}",
            modelJ, serialJ, fwJ,
            (unsigned)d.CRITICAL_WARNING,
            d.TEMPERATURE - 273.15,
            (unsigned)d.AVAILABLE_SPARE,
            (unsigned)d.AVAILABLE_SPARE_THRESHOLD,
            (unsigned)d.PERCENTAGE_USED,
            written, read,
            (unsigned long long)d.POWER_ON_HOURS[0],
            (unsigned long long)d.POWER_CYCLES[0],
            (unsigned long long)d.UNSAFE_SHUTDOWNS[0],
            (unsigned long long)d.MEDIA_ERRORS[0],
            (unsigned long long)d.NUM_ERROR_INFO_LOG_ENTRIES[0],
            (unsigned long long)d.HOST_WRITE_COMMANDS[0],
            (unsigned long long)d.HOST_READ_COMMANDS[0]);

        (*smart)->Release(smart);
        (*plug)->Release(plug);
        IOObjectRelease(svc);
        IOObjectRelease(iter);
        return g_json;
    }

    IOObjectRelease(iter);
    fill_error(-3, "没有找到支持 NVMe SMART 的磁盘");
    return g_json;
}
