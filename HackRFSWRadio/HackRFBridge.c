#include "HackRFBridge.h"

#include <libhackrf/hackrf.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RING_CAP (8 * 1024 * 1024)

typedef struct HackRFHandle {
    hackrf_device *device;
    pthread_mutex_t lock;
    uint8_t *ring;
    size_t cap;
    size_t read_pos;
    size_t write_pos;
    size_t count;
    int streaming;
    char serial[96];
    char firmware[80];
    char board[80];
} HackRFHandle;

static void set_err(char *out, int cap, const char *msg) {
    if (out == NULL || cap <= 0) {
        return;
    }
    snprintf(out, (size_t)cap, "%s", msg);
}

static void set_hackrf_err(char *out, int cap, const char *what, int code) {
    if (out == NULL || cap <= 0) {
        return;
    }
    snprintf(out, (size_t)cap, "%s: %s", what, hackrf_error_name(code));
}

static int clamp_lna(int db) {
    if (db < 0) db = 0;
    if (db > 40) db = 40;
    return (db / 8) * 8;
}

static int clamp_vga(int db) {
    if (db < 0) db = 0;
    if (db > 62) db = 62;
    return (db / 2) * 2;
}

static void ring_write(HackRFHandle *h, const uint8_t *src, int len) {
    if (len <= 0) {
        return;
    }
    pthread_mutex_lock(&h->lock);
    if ((size_t)len >= h->cap) {
        src += len - (int)h->cap;
        len = (int)h->cap;
        h->read_pos = 0;
        h->write_pos = 0;
        h->count = 0;
    } else if (h->count + (size_t)len > h->cap) {
        size_t drop = h->count + (size_t)len - h->cap;
        h->read_pos = (h->read_pos + drop) % h->cap;
        h->count -= drop;
    }

    size_t first = h->cap - h->write_pos;
    if (first > (size_t)len) {
        first = (size_t)len;
    }
    memcpy(h->ring + h->write_pos, src, first);
    if ((size_t)len > first) {
        memcpy(h->ring, src + first, (size_t)len - first);
    }
    h->write_pos = (h->write_pos + (size_t)len) % h->cap;
    h->count += (size_t)len;
    pthread_mutex_unlock(&h->lock);
}

static int rx_callback(hackrf_transfer *transfer) {
    HackRFHandle *h = (HackRFHandle *)transfer->rx_ctx;
    if (h == NULL || transfer->buffer == NULL || transfer->valid_length <= 0) {
        return 0;
    }
    ring_write(h, transfer->buffer, transfer->valid_length);
    return 0;
}

static void read_identity(HackRFHandle *h) {
    snprintf(h->board, sizeof(h->board), "HackRF");
    snprintf(h->firmware, sizeof(h->firmware), "—");
    snprintf(h->serial, sizeof(h->serial), "—");

    uint8_t id = BOARD_ID_UNDETECTED;
    if (hackrf_board_id_read(h->device, &id) == HACKRF_SUCCESS) {
        const char *name = hackrf_board_id_name((enum hackrf_board_id)id);
        if (name != NULL) {
            snprintf(h->board, sizeof(h->board), "%s", name);
        }
    }

    char version[64];
    memset(version, 0, sizeof(version));
    if (hackrf_version_string_read(h->device, version, (uint8_t)(sizeof(version) - 1)) == HACKRF_SUCCESS) {
        snprintf(h->firmware, sizeof(h->firmware), "%s", version);
    }

    read_partid_serialno_t sn;
    memset(&sn, 0, sizeof(sn));
    if (hackrf_board_partid_serialno_read(h->device, &sn) == HACKRF_SUCCESS) {
        snprintf(h->serial, sizeof(h->serial), "%08x%08x", sn.serial_no[2], sn.serial_no[3]);
    }
}

void *hackrf_bridge_open(char *error_out, int error_cap) {
    int status = hackrf_init();
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "hackrf_init", status);
        return NULL;
    }

    hackrf_device *device = NULL;
    status = hackrf_open(&device);
    if (status != HACKRF_SUCCESS || device == NULL) {
        set_hackrf_err(error_out, error_cap, "HACKRF_ERROR_NOT_FOUND", status);
        hackrf_exit();
        return NULL;
    }

    HackRFHandle *h = calloc(1, sizeof(HackRFHandle));
    if (h == NULL) {
        hackrf_close(device);
        hackrf_exit();
        set_err(error_out, error_cap, "内存不足");
        return NULL;
    }
    h->device = device;
    h->cap = RING_CAP;
    h->ring = calloc(1, h->cap);
    if (h->ring == NULL) {
        free(h);
        hackrf_close(device);
        hackrf_exit();
        set_err(error_out, error_cap, "内存不足");
        return NULL;
    }
    pthread_mutex_init(&h->lock, NULL);
    read_identity(h);
    return h;
}

static void stop_streaming(HackRFHandle *h) {
    if (h->streaming && h->device != NULL) {
        hackrf_stop_rx(h->device);
        h->streaming = 0;
    }
}

void hackrf_bridge_close(void *handle) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL) {
        return;
    }
    stop_streaming(h);
    if (h->device != NULL) {
        hackrf_close(h->device);
        h->device = NULL;
    }
    pthread_mutex_destroy(&h->lock);
    free(h->ring);
    free(h);
    hackrf_exit();
}

int hackrf_bridge_start(void *handle,
                        double sample_rate,
                        uint64_t freq_hz,
                        int lna_db,
                        int vga_db,
                        int amp,
                        char *error_out,
                        int error_cap) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL || h->device == NULL) {
        set_err(error_out, error_cap, "HackRF 未打开");
        return -1;
    }
    stop_streaming(h);

    int status = hackrf_set_sample_rate(h->device, sample_rate);
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "set_sample_rate", status);
        return status;
    }
    status = hackrf_set_freq(h->device, freq_hz);
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "set_freq", status);
        return status;
    }
    status = hackrf_set_lna_gain(h->device, (uint32_t)clamp_lna(lna_db));
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "set_lna_gain", status);
        return status;
    }
    status = hackrf_set_vga_gain(h->device, (uint32_t)clamp_vga(vga_db));
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "set_vga_gain", status);
        return status;
    }
    status = hackrf_set_amp_enable(h->device, amp ? 1 : 0);
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "set_amp", status);
        return status;
    }

    hackrf_bridge_flush(h);
    status = hackrf_start_rx(h->device, rx_callback, h);
    if (status != HACKRF_SUCCESS) {
        set_hackrf_err(error_out, error_cap, "start_rx", status);
        return status;
    }
    h->streaming = 1;
    return 0;
}

int hackrf_bridge_stop(void *handle) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL) {
        return -1;
    }
    stop_streaming(h);
    return 0;
}

int hackrf_bridge_set_freq(void *handle, uint64_t freq_hz) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL || h->device == NULL) {
        return -1;
    }
    return hackrf_set_freq(h->device, freq_hz);
}

int hackrf_bridge_set_sample_rate(void *handle, double sample_rate) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL || h->device == NULL) {
        return -1;
    }
    int was = h->streaming;
    stop_streaming(h);
    int status = hackrf_set_sample_rate(h->device, sample_rate);
    if (status != HACKRF_SUCCESS) {
        return status;
    }
    if (was) {
        hackrf_bridge_flush(h);
        status = hackrf_start_rx(h->device, rx_callback, h);
        h->streaming = (status == HACKRF_SUCCESS);
    }
    return status;
}

int hackrf_bridge_set_gains(void *handle, int lna_db, int vga_db, int amp) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL || h->device == NULL) {
        return -1;
    }
    int status = hackrf_set_lna_gain(h->device, (uint32_t)clamp_lna(lna_db));
    if (status != HACKRF_SUCCESS) {
        return status;
    }
    status = hackrf_set_vga_gain(h->device, (uint32_t)clamp_vga(vga_db));
    if (status != HACKRF_SUCCESS) {
        return status;
    }
    return hackrf_set_amp_enable(h->device, amp ? 1 : 0);
}

int hackrf_bridge_read(void *handle, uint8_t *dst, int count) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL || dst == NULL || count <= 0) {
        return 0;
    }
    pthread_mutex_lock(&h->lock);
    int n = count;
    if ((size_t)n > h->count) {
        n = (int)h->count;
    }
    size_t first = h->cap - h->read_pos;
    if (first > (size_t)n) {
        first = (size_t)n;
    }
    memcpy(dst, h->ring + h->read_pos, first);
    if ((size_t)n > first) {
        memcpy(dst + first, h->ring, (size_t)n - first);
    }
    h->read_pos = (h->read_pos + (size_t)n) % h->cap;
    h->count -= (size_t)n;
    pthread_mutex_unlock(&h->lock);
    return n;
}

void hackrf_bridge_flush(void *handle) {
    HackRFHandle *h = (HackRFHandle *)handle;
    if (h == NULL) {
        return;
    }
    pthread_mutex_lock(&h->lock);
    h->read_pos = 0;
    h->write_pos = 0;
    h->count = 0;
    pthread_mutex_unlock(&h->lock);
}

const char *hackrf_bridge_serial(void *handle) {
    HackRFHandle *h = (HackRFHandle *)handle;
    return h == NULL ? "" : h->serial;
}

const char *hackrf_bridge_firmware(void *handle) {
    HackRFHandle *h = (HackRFHandle *)handle;
    return h == NULL ? "" : h->firmware;
}

const char *hackrf_bridge_board(void *handle) {
    HackRFHandle *h = (HackRFHandle *)handle;
    return h == NULL ? "" : h->board;
}
