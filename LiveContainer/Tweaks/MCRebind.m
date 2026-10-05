#import "MCRebind.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

struct MCInterposeTuple {
    const void *replacement;
    const void *replacee;
};

extern void dyld_dynamic_interpose(const struct mach_header *mh,
                                   const struct MCInterposeTuple array[],
                                   size_t count) __attribute__((weak_import));

// Địa chỉ phải nằm trong đúng ảnh vừa hỏi. dlsym ảnh chính trả symbol đã bị
// interpose (trỏ sang MunChanger) — đó không phải hàm gốc.
static int MCAddrInImage(const void *addr, uint32_t index) {
    const struct mach_header *mh = _dyld_get_image_header(index);
    if (!mh || !addr) return 0;
    intptr_t slide = _dyld_get_image_vmaddr_slide(index);
    uintptr_t target = (uintptr_t)addr;
    const uint8_t *p;
    uint32_t ncmds;
    if (mh->magic == MH_MAGIC_64) {
        const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
        p = (const uint8_t *)(mh64 + 1);
        ncmds = mh64->ncmds;
    } else {
        p = (const uint8_t *)(mh + 1);
        ncmds = mh->ncmds;
    }
    for (uint32_t c = 0; c < ncmds; c++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmdsize < sizeof(*lc)) break;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            uintptr_t start = (uintptr_t)seg->vmaddr + (uintptr_t)slide;
            uintptr_t end = start + (uintptr_t)seg->vmsize;
            if (target >= start && target < end) return 1;
        }
        p += lc->cmdsize;
    }
    return 0;
}

// Chỉ ảnh đã nạp, RTLD_NOLOAD. Lần lồng nhau trả NULL, không dlsym.
// Hook sysctl/statfs không được gọi hàm này: malloc bên trong dlsym sẽ gọi lại hook.
void *MCLookupRealSymbol(const char *name) {
    if (!name) return NULL;
    static __thread int depth;
    if (depth > 0) return NULL;
    depth++;
    void *found = NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (mh && mh->filetype == MH_EXECUTE) continue;
        const char *path = _dyld_get_image_name(i);
        if (!path || strstr(path, "MunChanger.dylib")) continue;
        void *image = dlopen(path, RTLD_NOLOAD);
        if (!image) continue;
        void *sym = dlsym(image, name);
        if (!sym || !MCAddrInImage(sym, i)) continue;
        found = sym;
        break;
    }
    depth--;
    return found;
}

int MCPointerInSystemImage(const void *addr) {
    if (!addr) return 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (!MCAddrInImage(addr, i)) continue;
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (mh && mh->filetype == MH_EXECUTE) return 0;
        const char *path = _dyld_get_image_name(i);
        if (!path || strstr(path, "MunChanger")) return 0;
        return 1;
    }
    return 0;
}

static const struct mach_header *MCHeaderContaining(const void *addr) {
    if (!addr) return NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (MCAddrInImage(addr, i)) return _dyld_get_image_header(i);
    }
    return NULL;
}

void *MCInterposeReplacee(void *replacement) {
    if (!replacement) return NULL;
    const struct mach_header *mh = MCHeaderContaining((void *)MCInterposeReplacee);
    if (!mh || mh->magic != MH_MAGIC_64) return NULL;
    intptr_t slide = 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (_dyld_get_image_header(i) == mh) {
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
    const uint8_t *p = (const uint8_t *)(mh64 + 1);
    for (uint32_t c = 0; c < mh64->ncmds; c++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmdsize < sizeof(*lc)) break;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            const struct section_64 *sec = (const struct section_64 *)(seg + 1);
            for (uint32_t s = 0; s < seg->nsects; s++) {
                if (strncmp(sec[s].sectname, "__interpose", 16) != 0) continue;
                struct { void *repl; void *orig; } *tuples = (void *)((uintptr_t)sec[s].addr + (uintptr_t)slide);
                uint32_t n = sec[s].size / sizeof(*tuples);
                for (uint32_t t = 0; t < n; t++) {
                    if (tuples[t].repl == replacement && MCPointerInSystemImage(tuples[t].orig)) {
                        return tuples[t].orig;
                    }
                }
            }
        }
        p += lc->cmdsize;
    }
    return NULL;
}

static int MCReadULEB(const uint8_t **pp, const uint8_t *end, uint64_t *out) {
    const uint8_t *p = *pp;
    uint64_t result = 0;
    int bit = 0;
    while (p < end && bit <= 63) {
        uint8_t b = *p++;
        result |= (uint64_t)(b & 0x7f) << bit;
        if ((b & 0x80) == 0) {
            *pp = p;
            *out = result;
            return 1;
        }
        bit += 7;
    }
    *pp = end;
    return 0;
}

static const uint8_t *MCSkipSLEB(const uint8_t *p, const uint8_t *end) {
    while (p < end) {
        uint8_t b = *p++;
        if ((b & 0x80) == 0) break;
    }
    return p;
}

static int gMCRebindWrites = 0;

// file diagnostic — same Documents folder as mcapi.log, readable over SSH
static void MCRebindDebug(const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    NSString *home = NSHomeDirectory();
    if (home.length == 0) home = @"/tmp";
    NSString *path = [home stringByAppendingPathComponent:@"mcdebug.log"];
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) {
        fprintf(f, "%s %s\n", [[NSDate date] description].UTF8String, buf);
        fclose(f);
    }
}

static BOOL MCSymbolIs(const char *sym, const char *name) {
    if (!sym || !name || !name[0]) return 0;
    if (strcmp(sym, name) == 0) return 1;
    return sym[0] == '_' && strcmp(sym + 1, name) == 0;
}

static int MCSegmentAt(const struct mach_header_64 *mh, uint32_t index, struct segment_command_64 *out) {
    const uint8_t *p = (const uint8_t *)(mh + 1);
    uint32_t seen = 0;
    for (uint32_t c = 0; c < mh->ncmds; c++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmdsize < sizeof(*lc)) return 0;
        if (lc->cmd == LC_SEGMENT_64) {
            if (seen == index) {
                memcpy(out, lc, sizeof(*out));
                return 1;
            }
            seen++;
        }
        p += lc->cmdsize;
    }
    return 0;
}

static const uint8_t *MCMapFileOff(const struct mach_header_64 *mh, intptr_t slide, uint32_t fileoff) {
    const uint8_t *p = (const uint8_t *)(mh + 1);
    for (uint32_t c = 0; c < mh->ncmds; c++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmdsize < sizeof(*lc)) return NULL;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (fileoff >= seg->fileoff && fileoff - seg->fileoff < seg->filesize) {
                return (const uint8_t *)((uintptr_t)seg->vmaddr + (uintptr_t)slide + (fileoff - seg->fileoff));
            }
        }
        p += lc->cmdsize;
    }
    return NULL;
}

// __DATA của AppFake là một trang: khóa PROT_READ sẽ đóng băng objc/bss.
static void MCWriteDataSlot(uintptr_t addr, void *value) {
    gMCRebindWrites++;
    long page = sysconf(_SC_PAGESIZE);
    if (page < 4096) page = 16384;
    uintptr_t pageStart = addr & ~((uintptr_t)page - 1);
    if (mprotect((void *)pageStart, (size_t)page, PROT_READ | PROT_WRITE) != 0) return;
    *(void **)addr = value;
}

void MCRedirectLazySymbol(const char *symbol, void *replacement) {
    if (!symbol || !replacement) return;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->magic != MH_MAGIC_64 || mh->filetype != MH_EXECUTE) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
        const uint8_t *p = (const uint8_t *)(mh64 + 1);
        const struct dyld_info_command *info = NULL;
        for (uint32_t c = 0; c < mh64->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmdsize < sizeof(*lc)) break;
            if (lc->cmd == LC_DYLD_INFO || lc->cmd == LC_DYLD_INFO_ONLY) {
                info = (const struct dyld_info_command *)lc;
                break;
            }
            p += lc->cmdsize;
        }
        if (!info || info->lazy_bind_size < 2) continue;
        const uint8_t *bind = MCMapFileOff(mh64, slide, info->lazy_bind_off);
        if (!bind) continue;
        const uint8_t *end = bind + info->lazy_bind_size;
        const uint8_t *cursor = bind;
        uint32_t segIndex = 0;
        uint64_t segOff = 0;
        const char *sym = NULL;
        int writes = 0;
        while (cursor < end && writes < 8) {
            uint8_t raw = *cursor++;
            uint8_t op = raw & BIND_OPCODE_MASK;
            uint8_t imm = raw & BIND_IMMEDIATE_MASK;
            if (op == BIND_OPCODE_DONE) {
                continue;
            } else if (op == BIND_OPCODE_SET_DYLIB_ORDINAL_IMM || op == BIND_OPCODE_SET_DYLIB_SPECIAL_IMM || op == BIND_OPCODE_SET_TYPE_IMM) {
                continue;
            } else if (op == BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB || op == BIND_OPCODE_ADD_ADDR_ULEB) {
                uint64_t add = 0;
                if (!MCReadULEB(&cursor, end, &add)) break;
                if (op == BIND_OPCODE_ADD_ADDR_ULEB) segOff += add;
            } else if (op == BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM) {
                const uint8_t *s = cursor;
                while (cursor < end && *cursor) cursor++;
                if (cursor >= end) break;
                sym = (const char *)s;
                cursor++;
            } else if (op == BIND_OPCODE_SET_ADDEND_SLEB) {
                cursor = MCSkipSLEB(cursor, end);
            } else if (op == BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB) {
                uint64_t off = 0;
                if (!MCReadULEB(&cursor, end, &off)) break;
                segIndex = imm;
                segOff = off;
            } else if (op == BIND_OPCODE_DO_BIND || op == BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB
                       || op == BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED
                       || op == BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB) {
                uint64_t times = 1;
                uint64_t skip = 0;
                uint64_t extra = 0;
                if (op == BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB) {
                    if (!MCReadULEB(&cursor, end, &extra)) break;
                } else if (op == BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED) {
                    skip = (uint64_t)imm * sizeof(void *);
                } else if (op == BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB) {
                    if (!MCReadULEB(&cursor, end, &times) || !MCReadULEB(&cursor, end, &skip)) break;
                }
                if (times > 64) times = 64;
                for (uint64_t n = 0; n < times && writes < 8; n++) {
                    if (MCSymbolIs(sym, symbol)) {
                        struct segment_command_64 seg;
                        if (MCSegmentAt(mh64, segIndex, &seg) && strcmp(seg.segname, "__DATA") == 0
                            && segOff + sizeof(void *) <= seg.vmsize) {
                            uintptr_t addr = (uintptr_t)seg.vmaddr + (uintptr_t)slide + (uintptr_t)segOff;
                            MCWriteDataSlot(addr, replacement);
                            writes++;
                        }
                    }
                    if (op == BIND_OPCODE_DO_BIND) segOff += sizeof(void *);
                    else if (op == BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB) segOff += sizeof(void *) + extra;
                    else segOff += sizeof(void *) + skip;
                }
            } else {
                break;
            }
        }
    }
}

void MCRedirectMainImport(void *from, void *to) {
    if (!from || !to || from == to) return;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->magic != MH_MAGIC_64 || mh->filetype != MH_EXECUTE) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
        const uint8_t *p = (const uint8_t *)(mh64 + 1);
        long page = sysconf(_SC_PAGESIZE);
        if (page < 4096) page = 16384;
        for (uint32_t c = 0; c < mh64->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmdsize < sizeof(*lc)) break;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                const struct section_64 *sec = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    int got = strncmp(sec[s].sectname, "__la_symbol_ptr", 16) == 0
                              || strncmp(sec[s].sectname, "__got", 16) == 0;
                    if (!got || sec[s].size < sizeof(void *)) continue;
                    uintptr_t start = (uintptr_t)sec[s].addr + (uintptr_t)slide;
                    void **slot = (void **)start;
                    size_t n = (size_t)sec[s].size / sizeof(void *);
                    int hit = 0;
                    for (size_t k = 0; k < n; k++) {
                        if (slot[k] == from) { hit = 1; break; }
                    }
                    if (!hit) continue;
                    uintptr_t pageStart = start & ~((uintptr_t)page - 1);
                    size_t span = (start + (size_t)sec[s].size) - pageStart;
                    if (mprotect((void *)pageStart, span, PROT_READ | PROT_WRITE) != 0) continue;
                    for (size_t k = 0; k < n; k++) {
                        if (slot[k] == from) slot[k] = to;
                    }
                    mprotect((void *)pageStart, span, PROT_READ | PROT_WRITE);
                }
            }
            p += lc->cmdsize;
        }
    }
}

BOOL MCRebindSymbol(const char *name, void *replacement, void **originalOut) {
    if (!name || !replacement) {
        return NO;
    }
    void *orig = MCLookupRealSymbol(name);
    if (!orig || orig == replacement) {
        orig = dlsym(RTLD_NEXT, name);
    }
    if (!orig || orig == replacement) {
        orig = dlsym(RTLD_DEFAULT, name);
    }
    if (orig == replacement) {
        orig = NULL;
    }
    if (originalOut) {
        *originalOut = orig;
    }
    int interposed = 0;
    // Preferred: litehook global rebind (works on jailed iOS 16+ incl. images
    // loaded later via gRebinds/Dyld.m; LC itself uses it for guest hooks).
    // Resolved dynamically — litehook links into the main LC binary.
    typedef void (*mc_litehook_rebind_t)(const void *, void *, void *, void *);
    static mc_litehook_rebind_t mcLitehookRebind;
    static int mcLitehookTried;
    if (!mcLitehookTried) {
        mcLitehookTried = 1;
        mcLitehookRebind = (mc_litehook_rebind_t)dlsym(RTLD_DEFAULT, "litehook_rebind_symbol");
    }
    if (mcLitehookRebind && orig) {
        mcLitehookRebind(NULL /* LITEHOOK_REBIND_GLOBAL */, orig, replacement, NULL);
        interposed = 1;
    } else if (&dyld_dynamic_interpose != NULL) {
        void *target = orig ?: dlsym(RTLD_DEFAULT, name);
        if (target) {
            struct MCInterposeTuple tuple = { replacement, target };
            uint32_t count = _dyld_image_count();
            for (uint32_t i = 0; i < count; i++) {
                const struct mach_header *mh = _dyld_get_image_header(i);
                if (!mh) continue;
                dyld_dynamic_interpose(mh, &tuple, 1);
            }
            interposed = 2;
        }
    }
    // GOT/lazy fallback: rewrite already-bound pointers in the main executable.
    // On iOS 16 dyld_dynamic_interpose may be unavailable (weak import == NULL)
    // or ignored for the app's own GOT; the slot rewrite needs no dyld help.
    gMCRebindWrites = 0;
    MCRedirectLazySymbol(name, replacement);
    int lazyWrites = gMCRebindWrites;
    gMCRebindWrites = 0;
    if (orig) {
        MCRedirectMainImport(orig, replacement);
    }
    int gotWrites = gMCRebindWrites;
    gMCRebindWrites = 0;
    MCRebindDebug("rebind %-16s orig=%p method=%d(1=litehook,2=interpose) lazy=%d got=%d",
                  name, orig, interposed, lazyWrites, gotWrites);
    return YES;
}
