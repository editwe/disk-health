#ifndef HEALTH_READER_H
#define HEALTH_READER_H

#ifdef __cplusplus
extern "C" {
#endif

/* Returns a static JSON buffer describing the internal NVMe SSD's health.
   Caller must not free the result. */
const char *dh_read_health_json(void);

#ifdef __cplusplus
}
#endif

#endif
