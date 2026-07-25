// steam_api64.dll shim for PICO PARK 2 (gbe_fork experimental).
//
// WHY: gbe_fork's Windows SteamInput backend polls XInput
// (libs/gamepad/gamepad.c, XINPUT9_1_0), which is hard-capped at 4
// controllers (XUSER_MAX_COUNT). PICO PARK 2 supports up to 8 local
// players and routes ALL gameplay pads through ISteamInput
// (SteamNative.dll -> SteamInternal_FindOrCreateUserInterface(
// "SteamInput006") -> ISteamInput006 vtable), so only 4 of 8 pads ever
// worked.
//
// WHAT: this shim is built AS steam_api64.dll. Every export is forwarded
// verbatim to the real gbe_fork emu (renamed steam_api64_o.dll) via a
// generated .def (pure loader redirection, no ABI surface), EXCEPT
// SteamInternal_FindOrCreateUserInterface: for the "SteamInput006"
// version string we return our own ISteamInput006 implementation that
// enumerates up to 8 pads via DirectInput8 (wine, uncapped -- unlike
// XInput) and maps them through the same "GameControls" action set the
// game asks for (verified via a gbe_fork debug STEAM_LOG trace). Every
// other interface still comes from the real emu, so networking, stats,
// achievements, etc. are unchanged.
//
// The action<->input mapping mirrors steam_settings/controller/
// GameControls.txt (the config the stock XInput path uses):
//   Action_A=A Action_B=B Action_X=X Action_Y=Y Action_L=LB Action_R=RB
//   Action_Start=START Action_{Up,Down,Left,Right}=DPAD
//   Action_Joystick=left stick (analog)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <vector>

#include "steam/isteaminput.h"

// ---- trace ----------------------------------------------------------
static void trace(const char *fmt, ...) {
    char buf[512];
    va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    OutputDebugStringA(buf);
}

// ---- action model ---------------------------------------------------
// Digital action handles are 1..ND, analog handles 101.., action set = 1.
enum : uint64_t {
    ACTSET_GAMECONTROLS = 1,
    ANALOG_JOYSTICK     = 101,
};

// Digital action -> DInput probe. kind: 0 = button index, 1 = POV dir.
struct DigitalMap { const char *name; int kind; int arg; };
static const DigitalMap kDigital[] = {
    {"Action_A",     0, 0},   {"Action_B",     0, 1},
    {"Action_X",     0, 2},   {"Action_Y",     0, 3},
    {"Action_L",     0, 4},   {"Action_R",     0, 5},
    {"Action_Start", 0, 7},
    {"Action_Up",    1, 0},   {"Action_Down",  1, 1},
    {"Action_Left",  1, 2},   {"Action_Right", 1, 3},
};
static const int kNumDigital = (int)(sizeof(kDigital) / sizeof(kDigital[0]));

// ---- DirectInput controller table -----------------------------------
static const int kMaxPads = 8;
struct Pad {
    IDirectInputDevice8A *dev = nullptr;
    DIJOYSTATE2 state{};
    bool ok = false;
};
static IDirectInput8A *g_di = nullptr;
static Pad g_pads[kMaxPads];
static int g_numPads = 0;
static bool g_initialised = false;

static BOOL CALLBACK enum_cb(const DIDEVICEINSTANCEA *inst, void *ctx) {
    if (g_numPads >= kMaxPads) return DIENUM_STOP;
    IDirectInputDevice8A *dev = nullptr;
    if (FAILED(g_di->CreateDevice(inst->guidInstance, &dev, nullptr)))
        return DIENUM_CONTINUE;
    dev->SetDataFormat(&c_dfDIJoystick2);
    // Symmetric [-1000,1000] range on the primary stick axes.
    DIPROPRANGE r;
    r.diph.dwSize = sizeof(r); r.diph.dwHeaderSize = sizeof(r.diph);
    r.diph.dwHow = DIPH_DEVICE; r.diph.dwObj = 0;
    r.lMin = -1000; r.lMax = 1000;
    dev->SetProperty(DIPROP_RANGE, &r.diph);
    dev->Acquire();
    g_pads[g_numPads].dev = dev;
    g_pads[g_numPads].ok = true;
    g_numPads++;
    trace("[siShim] enumerated pad %d\n", g_numPads);
    return DIENUM_CONTINUE;
}

static void di_init() {
    if (g_di) return;
    HRESULT hr = DirectInput8Create(GetModuleHandle(nullptr),
        DIRECTINPUT_VERSION, IID_IDirectInput8A, (void **)&g_di, nullptr);
    if (FAILED(hr) || !g_di) { trace("[siShim] DI8Create failed %lx\n", hr); return; }
    g_di->EnumDevices(DI8DEVCLASS_GAMECTRL, enum_cb, nullptr, DIEDFL_ATTACHEDONLY);
    trace("[siShim] DirectInput enumerated %d pads\n", g_numPads);
}

static void di_poll() {
    for (int i = 0; i < g_numPads; i++) {
        Pad &p = g_pads[i];
        if (!p.dev) continue;
        if (FAILED(p.dev->Poll())) { p.dev->Acquire(); p.dev->Poll(); }
        if (FAILED(p.dev->GetDeviceState(sizeof(DIJOYSTATE2), &p.state)))
            p.ok = false;
        else
            p.ok = true;
    }
}

// inputHandle for a controller is (index+1); map back to slot.
static int slot_of(InputHandle_t h) {
    int s = (int)h - 1;
    return (s >= 0 && s < g_numPads) ? s : -1;
}

static bool pov_dir(DWORD pov, int dir) {
    if (LOWORD(pov) == 0xFFFF) return false;   // centered
    int a = (int)pov;                          // centidegrees, 0 = up
    switch (dir) {
        case 0: return a >= 31500 || a <= 4500;            // up
        case 1: return a >= 13500 && a <= 22500;           // down
        case 2: return a >= 22500 && a <= 31500;           // left
        case 3: return a >= 4500  && a <= 13500;           // right
    }
    return false;
}

// ---- ISteamInput006 implementation ----------------------------------
class CSteamInputShim : public ISteamInput {
public:
    bool Init(bool) override { di_init(); g_initialised = true;
        trace("[siShim] Init -> %d pads\n", g_numPads); return true; }
    bool Shutdown() override { return true; }
    bool SetInputActionManifestFilePath(const char *) override { return true; }
    void RunFrame(bool) override { if (g_initialised) di_poll(); }
    bool BWaitForData(bool, uint32) override { return false; }
    bool BNewDataAvailable() override { return true; }

    int GetConnectedControllers(InputHandle_t *handlesOut) override {
        if (!g_initialised) { di_init(); g_initialised = true; }
        di_poll();
        int n = 0;
        for (int i = 0; i < g_numPads; i++)
            if (g_pads[i].ok && handlesOut) handlesOut[n++] = (InputHandle_t)(i + 1);
        return n;
    }
    void EnableDeviceCallbacks() override {}
    void EnableActionEventCallbacks(SteamInputActionEventCallbackPointer) override {}

    InputActionSetHandle_t GetActionSetHandle(const char *) override { return ACTSET_GAMECONTROLS; }
    void ActivateActionSet(InputHandle_t, InputActionSetHandle_t) override {}
    InputActionSetHandle_t GetCurrentActionSet(InputHandle_t) override { return ACTSET_GAMECONTROLS; }
    void ActivateActionSetLayer(InputHandle_t, InputActionSetHandle_t) override {}
    void DeactivateActionSetLayer(InputHandle_t, InputActionSetHandle_t) override {}
    void DeactivateAllActionSetLayers(InputHandle_t) override {}
    int GetActiveActionSetLayers(InputHandle_t, InputActionSetHandle_t *) override { return 0; }

    InputDigitalActionHandle_t GetDigitalActionHandle(const char *name) override {
        for (int i = 0; i < kNumDigital; i++)
            if (name && strcmp(name, kDigital[i].name) == 0)
                return (InputDigitalActionHandle_t)(i + 1);
        return 0;
    }
    InputDigitalActionData_t GetDigitalActionData(InputHandle_t h, InputDigitalActionHandle_t a) override {
        InputDigitalActionData_t d{}; d.bState = false; d.bActive = true;
        int s = slot_of(h); int idx = (int)a - 1;
        if (s < 0 || idx < 0 || idx >= kNumDigital) { d.bActive = false; return d; }
        const DigitalMap &m = kDigital[idx];
        const DIJOYSTATE2 &js = g_pads[s].state;
        if (m.kind == 0) d.bState = (js.rgbButtons[m.arg] & 0x80) != 0;
        else             d.bState = pov_dir(js.rgdwPOV[0], m.arg);
        return d;
    }
    int GetDigitalActionOrigins(InputHandle_t, InputActionSetHandle_t, InputDigitalActionHandle_t, EInputActionOrigin *) override { return 0; }
    const char *GetStringForDigitalActionName(InputDigitalActionHandle_t) override { return ""; }

    InputAnalogActionHandle_t GetAnalogActionHandle(const char *name) override {
        if (name && strcmp(name, "Action_Joystick") == 0) return ANALOG_JOYSTICK;
        return 0;
    }
    InputAnalogActionData_t GetAnalogActionData(InputHandle_t h, InputAnalogActionHandle_t a) override {
        InputAnalogActionData_t d{}; d.eMode = k_EInputSourceMode_JoystickMove;
        d.x = 0; d.y = 0; d.bActive = true;
        int s = slot_of(h);
        if (s < 0 || a != ANALOG_JOYSTICK) { d.bActive = false; return d; }
        const DIJOYSTATE2 &js = g_pads[s].state;
        d.x =  (float)js.lX / 1000.0f;   // range set to [-1000,1000]
        d.y = -(float)js.lY / 1000.0f;   // DInput Y is down-positive; flip
        return d;
    }
    int GetAnalogActionOrigins(InputHandle_t, InputActionSetHandle_t, InputAnalogActionHandle_t, EInputActionOrigin *) override { return 0; }
    const char *GetGlyphPNGForActionOrigin(EInputActionOrigin, ESteamInputGlyphSize, uint32) override { return ""; }
    const char *GetGlyphSVGForActionOrigin(EInputActionOrigin, uint32) override { return ""; }
    const char *GetGlyphForActionOrigin_Legacy(EInputActionOrigin) override { return ""; }
    const char *GetStringForActionOrigin(EInputActionOrigin) override { return ""; }
    const char *GetStringForAnalogActionName(InputAnalogActionHandle_t) override { return ""; }
    void StopAnalogActionMomentum(InputHandle_t, InputAnalogActionHandle_t) override {}
    InputMotionData_t GetMotionData(InputHandle_t) override { InputMotionData_t m{}; return m; }

    void TriggerVibration(InputHandle_t, unsigned short, unsigned short) override {}
    void TriggerVibrationExtended(InputHandle_t, unsigned short, unsigned short, unsigned short, unsigned short) override {}
    void TriggerSimpleHapticEvent(InputHandle_t, EControllerHapticLocation, uint8, char, uint8, char) override {}
    void SetLEDColor(InputHandle_t, uint8, uint8, uint8, unsigned int) override {}
    void Legacy_TriggerHapticPulse(InputHandle_t, ESteamControllerPad, unsigned short) override {}
    void Legacy_TriggerRepeatedHapticPulse(InputHandle_t, ESteamControllerPad, unsigned short, unsigned short, unsigned short, unsigned int) override {}

    bool ShowBindingPanel(InputHandle_t) override { return false; }
    ESteamInputType GetInputTypeForHandle(InputHandle_t h) override {
        return slot_of(h) >= 0 ? k_ESteamInputType_XBox360Controller : k_ESteamInputType_Unknown;
    }
    InputHandle_t GetControllerForGamepadIndex(int nIndex) override { return (InputHandle_t)(nIndex + 1); }
    int GetGamepadIndexForController(InputHandle_t h) override { int s = slot_of(h); return s >= 0 ? s : -1; }
    const char *GetStringForXboxOrigin(EXboxOrigin) override { return ""; }
    const char *GetGlyphForXboxOrigin(EXboxOrigin) override { return ""; }
    EInputActionOrigin GetActionOriginFromXboxOrigin(InputHandle_t, EXboxOrigin) override { return k_EInputActionOrigin_None; }
    EInputActionOrigin TranslateActionOrigin(ESteamInputType, EInputActionOrigin eSourceOrigin) override { return eSourceOrigin; }
    bool GetDeviceBindingRevision(InputHandle_t, int *, int *) override { return false; }
    uint32 GetRemotePlaySessionID(InputHandle_t) override { return 0; }
    uint16 GetSessionInputConfigurationSettings() override { return 0; }
    void SetDualSenseTriggerEffect(InputHandle_t, const ScePadTriggerEffectParam *) override {}
};

static CSteamInputShim g_shim;

// ---- intercepting export --------------------------------------------
// SteamNative.dll imports SteamInternal_FindOrCreateUserInterface from
// steam_api64.dll and calls the returned ISteamInput006 vtable. We hand
// it our object for that one interface and delegate everything else to
// the real emu.
typedef void *(*FindOrCreate_t)(HSteamUser, const char *);
static FindOrCreate_t g_realFindOrCreate = nullptr;

extern "C" __declspec(dllexport)
void *SteamInternal_FindOrCreateUserInterface(HSteamUser hUser, const char *version) {
    if (version && strcmp(version, STEAMINPUT_INTERFACE_VERSION) == 0) {
        trace("[siShim] handing our ISteamInput006 to game\n");
        return (void *)static_cast<ISteamInput *>(&g_shim);
    }
    if (g_realFindOrCreate) return g_realFindOrCreate(hUser, version);
    return nullptr;
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        HMODULE real = LoadLibraryA("steam_api64_o.dll");
        if (real)
            g_realFindOrCreate = (FindOrCreate_t)GetProcAddress(real, "SteamInternal_FindOrCreateUserInterface");
        trace("[siShim] attached, real emu %p findorcreate %p\n", (void *)real, (void *)g_realFindOrCreate);
    }
    return TRUE;
}
