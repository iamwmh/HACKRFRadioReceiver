#pragma once

#include <stdint.h>
#include <lame/lame.h>

/// Opaque HackRF session. All functions except the RX callback are serialized by the caller.
void *hackrf_bridge_open(char *error_out, int error_cap);
void hackrf_bridge_close(void *handle);

int hackrf_bridge_start(void *handle,
                        double sample_rate,
                        uint64_t freq_hz,
                        int lna_db,
                        int vga_db,
                        int amp,
                        char *error_out,
                        int error_cap);
int hackrf_bridge_stop(void *handle);

int hackrf_bridge_set_freq(void *handle, uint64_t freq_hz);
int hackrf_bridge_set_sample_rate(void *handle, double sample_rate);
int hackrf_bridge_set_gains(void *handle, int lna_db, int vga_db, int amp);

/// Copies up to `count` bytes of interleaved signed 8-bit I/Q. Returns bytes copied.
int hackrf_bridge_read(void *handle, uint8_t *dst, int count);
void hackrf_bridge_flush(void *handle);

const char *hackrf_bridge_serial(void *handle);
const char *hackrf_bridge_firmware(void *handle);
const char *hackrf_bridge_board(void *handle);
