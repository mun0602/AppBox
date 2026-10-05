#import "MCConfig.h"
#import "MCRebind.h"

#import <dlfcn.h>
#import <errno.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/types.h>
#import <unistd.h>

#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

typedef int (*MCPtraceFn)(int request, pid_t pid, caddr_t addr, int data);
typedef int (*MCPosixSpawnFn)(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                              const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);
typedef int (*MCExecveFn)(const char *path, char *const argv[], char *const envp[]);
typedef pid_t (*MCForkFn)(void);

static MCPtraceFn gOrigPtrace;
static MCPosixSpawnFn gOrigPosixSpawn;
static MCPosixSpawnFn gOrigPosixSpawnp;
static MCExecveFn gOrigExecve;
static MCForkFn gOrigFork;

static BOOL MCIsForbiddenSpawn(const char *path) {
    if (!path || path[0] == '\0') {
        return NO;
    }
    const char *const shells[] = {
        "/bin/sh",
        "/bin/bash",
        "/bin/zsh",
        "sh",
        "bash",
        "/usr/bin/bash",
        "/var/jb/bin/bash",
        "/var/jb/bin/sh",
    };
    for (size_t i = 0; i < sizeof(shells) / sizeof(shells[0]); i++) {
        if (strcmp(path, shells[i]) == 0 || strstr(path, shells[i]) != NULL) {
            return YES;
        }
    }
    return NO;
}

// `getenv` hook chỉ ẩn *biến* DYLD_INSERT_LIBRARIES khỏi lời gọi của app, nhưng
// kernel vẫn truyền nguyên môi trường sang process con — tức dylib vẫn nạp vào
// helper/XPC, nơi ta không kiểm soát được container lẫn entitlement, và mỗi
// process sẽ mang một "dấu vân tay" riêng. Strip DYLD_* khi spawn là cách chắc
// chắn nhất: child không nạp dylib thì không có gì để lệch.
extern char **environ;

static char **MCCopySanitizedEnv(char *const envp[]) {
    char **src = envp ? (char **)envp : environ;
    if (src == NULL) {
        return NULL;
    }
    size_t n = 0;
    while (src[n] != NULL) {
        n++;
    }
    char **out = (char **)calloc(n + 1, sizeof(char *));
    if (out == NULL) {
        return NULL;
    }
    size_t w = 0;
    for (size_t i = 0; i < n; i++) {
        if (src[i] == NULL || strncmp(src[i], "DYLD_", 5) == 0) {
            continue;
        }
        char *copy = strdup(src[i]);
        if (copy == NULL) {
            break; // hết bộ nhớ: dừng, vẫn kết thúc NULL ở dưới
        }
        out[w++] = copy;
    }
    out[w] = NULL;
    return out;
}

static void MCFreeSanitizedEnv(char **env) {
    if (env == NULL) {
        return;
    }
    for (size_t i = 0; env[i] != NULL; i++) {
        free(env[i]);
    }
    free(env);
}

static int MCHookedPtrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == PT_DENY_ATTACH) {
        return 0;
    }
    MCPtraceFn fn = (gOrigPtrace && gOrigPtrace != MCHookedPtrace) ? gOrigPtrace : (MCPtraceFn)dlsym(RTLD_DEFAULT, "ptrace");
    return fn ? fn(request, pid, addr, data) : 0;
}

static int MCHookedPosixSpawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                              const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if (MCIsForbiddenSpawn(path)) {
        errno = EPERM;
        return EPERM;
    }
    MCPosixSpawnFn fn = (gOrigPosixSpawn && gOrigPosixSpawn != MCHookedPosixSpawn) ? gOrigPosixSpawn : (MCPosixSpawnFn)dlsym(RTLD_DEFAULT, "posix_spawn");
    if (!fn) return EPERM;
    char **env = MCCopySanitizedEnv(envp);
    int rc = fn(pid, path, actions, attrp, argv, env ? env : envp);
    MCFreeSanitizedEnv(env);
    return rc;
}

static int MCHookedPosixSpawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                               const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if (MCIsForbiddenSpawn(file)) {
        errno = EPERM;
        return EPERM;
    }
    MCPosixSpawnFn fn = (gOrigPosixSpawnp && gOrigPosixSpawnp != MCHookedPosixSpawnp) ? gOrigPosixSpawnp : (MCPosixSpawnFn)dlsym(RTLD_DEFAULT, "posix_spawnp");
    if (!fn) return EPERM;
    char **env = MCCopySanitizedEnv(envp);
    int rc = fn(pid, file, actions, attrp, argv, env ? env : envp);
    MCFreeSanitizedEnv(env);
    return rc;
}

static int MCHookedExecve(const char *path, char *const argv[], char *const envp[]) {
    if (MCIsForbiddenSpawn(path)) {
        errno = EPERM;
        return -1;
    }
    MCExecveFn fn = (gOrigExecve && gOrigExecve != MCHookedExecve) ? gOrigExecve : (MCExecveFn)dlsym(RTLD_DEFAULT, "execve");
    if (!fn) return -1;
    char **env = MCCopySanitizedEnv(envp);
    int rc = fn(path, argv, env ? env : envp);
    MCFreeSanitizedEnv(env);
    return rc;
}

static pid_t MCHookedFork(void) {
    errno = EPERM;
    return -1;
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

extern int ptrace(int request, pid_t pid, caddr_t addr, int data);
extern pid_t fork(void);
DYLD_INTERPOSE(MCHookedPtrace, ptrace)
DYLD_INTERPOSE(MCHookedFork, fork)

void MCHookAntiDebugInstall(void) {
    static BOOL gHooked;
    if (gHooked) {
        return;
    }
    gHooked = YES;

    MCRebindSymbol("ptrace", (void *)MCHookedPtrace, (void **)&gOrigPtrace);
    MCRebindSymbol("posix_spawn", (void *)MCHookedPosixSpawn, (void **)&gOrigPosixSpawn);
    MCRebindSymbol("posix_spawnp", (void *)MCHookedPosixSpawnp, (void **)&gOrigPosixSpawnp);
    MCRebindSymbol("execve", (void *)MCHookedExecve, (void **)&gOrigExecve);
    MCRebindSymbol("fork", (void *)MCHookedFork, (void **)&gOrigFork);
}
