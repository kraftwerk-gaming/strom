// Minimal steamclient.so stub for Proton outside Steam.
//
// Proton's lsteamclient unixlib hardcodes $HOME/.steam/sdk{32,64}/steamclient.so
// and asserts on dlopen failure (lsteamclient/unixlib.h's STEAMCLIENT_CALL macro
// does assert(!status)). This stub satisfies the ABI surface Proton's steam.exe
// touches on startup so the assertion never fires.
//
// p_CreateInterface returns a vtable whose CreateSteamPipe returns 0, which
// makes Proton's steamclient_init_registry take its "Failed to connect to
// Steam" branch and return cleanly without touching any other methods.

#include <cstdint>

namespace {

class StubSteamClient {
public:
    virtual int32_t CreateSteamPipe() { return 0; }
    virtual bool BReleaseSteamPipe(int32_t) { return false; }
    virtual int32_t ConnectToGlobalUser(int32_t) { return 0; }
};

StubSteamClient g_stub;

}

extern "C" {

void *CreateInterface(const char *, int *return_code) {
    if (return_code) *return_code = 0;
    return &g_stub;
}

int8_t Steam_BGetCallback(int32_t, void *, int32_t *) { return 0; }
int8_t Steam_GetAPICallResult(int32_t, uint64_t, void *, int, int, int8_t *) { return 0; }
int8_t Steam_FreeLastCallback(int32_t) { return 0; }
void Steam_ReleaseThreadLocalMemory(int) {}
bool Steam_IsKnownInterface(const char *) { return false; }
void Steam_NotifyMissingInterface(int32_t, const char *) {}

}
