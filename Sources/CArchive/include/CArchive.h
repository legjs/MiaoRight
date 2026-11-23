#pragma once
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <time.h>

// macOS ships libarchive and its linker stub, but omits these C headers from the SDK.
// Declarations match libarchive's public archive.h and archive_entry.h.
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_format_zip_seekable(struct archive *);
int archive_read_support_format_7zip(struct archive *);
int archive_read_support_format_rar(struct archive *);
int archive_read_support_format_rar5(struct archive *);
int archive_read_support_format_tar(struct archive *);
int archive_read_support_format_cpio(struct archive *);
int archive_read_support_filter_gzip(struct archive *);
int archive_read_support_filter_bzip2(struct archive *);
int archive_read_support_filter_xz(struct archive *);
int archive_read_support_format_empty(struct archive *);
int archive_read_support_format_raw(struct archive *);
int archive_format(struct archive *);
int archive_filter_code(struct archive *, int);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
const char *archive_entry_pathname(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
int archive_entry_mtime_is_set(struct archive_entry *);

enum { CArchiveOK = 0, CArchiveEOF = 1, CArchiveWarn = -20,
       CArchiveRaw = 0x90000, CArchiveEmpty = 0x60000 };
