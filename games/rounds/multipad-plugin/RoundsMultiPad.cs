// RoundsMultiPad: BepInEx 5 Harmony plugin that restores multi-pad
// lobby join in ROUNDS under Proton/wine.
//
// Why this exists:
//   ROUNDS uses InControl for pad input. InControl's setup prefers
//   NativeInputDeviceManager (InControlNative.dll → Win32 HID); when
//   that manager succeeds at Enable() it suppresses the fallback
//   UnityInputDeviceManager entirely. Under wine the native HID
//   probe reports success but never enumerates the actual evdev
//   pads, leaving InputManager.ActiveDevices permanently empty. The
//   game's lobby loop (PlayerAssigner.LateUpdate) iterates that
//   list to spawn pad-bound players, so no pad can join.
//
// Fix:
//   After InControl finishes its own setup, unconditionally add a
//   UnityInputDeviceManager. That manager reads pad state through
//   Unity's joystick API (Input.GetKey("joystick N button M"),
//   Input.GetAxisRaw("joystick N analog M")), which we have already
//   verified works under wine (the ControllerSupport plugin reads
//   the same API to drive its in-match cursor). Both managers
//   coexist in InputManager.deviceManagers; the native one stays
//   silent and the Unity one populates ActiveDevices with real
//   UnityInputDevice instances. The lobby's existing pad-join path
//   then works unchanged.
//
// Diagnostic mode (this iteration):
//   The previous "wine duplicates one XInput pad as Xbox 360 +
//   XBox One" theory was wrong. User-reported symptoms are:
//     • wired Xbox 360 pad delivers no input at all
//     • Switch Pro pad only fires A/B; no D-pad, no sticks
//   With both 360-class pads ALSO labelled identically ("Xbox 360
//   Controller") by InControl, the name-pattern dedupe heuristic
//   never matched anything anyway. It is now OFF by default and
//   only re-enables when ROUNDS_MULTIPAD_DEDUPE=1.
//
//   Instead, every device emitted by UnityInputDeviceManager is
//   logged exhaustively (JoystickId, profile name/meta, per-source
//   AnalogIndex/ButtonIndex, live Input.GetAxisRaw / GetKey value)
//   so a retest can match a Unity device to the physical pad by
//   pressing one button at a time and reading the log.
//
// Note: this codebase ships a *fork* of InControl with reshuffled
// internals — UnityInputDevice has public `JoystickId` (no Profile
// property; uses a private `profile` field of type
// UnityInputDeviceProfileBase), and the InControl analog/button
// sources expose `AnalogIndex` / `ButtonIndex` as public fields
// (not the upstream private `analogId` / `buttonId`). The
// introspector reads the private profile field via reflection and
// the indices directly.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using InControl;
using UnityEngine;

namespace RoundsMultiPad
{
    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public class RoundsMultiPadPlugin : BaseUnityPlugin
    {
        public const string PluginGuid = "strom.rounds.multipad";
        public const string PluginName = "RoundsMultiPad";
        public const string PluginVersion = "1.0.0";

        // Dedupe heuristic: drop "XBox One Controller"
        // UnityInputDevices when an "Xbox 360 Controller" with the same
        // sort group is also attached, on the assumption that wine
        // exposes the same physical pad under both names. Default ON
        // — confirmed via user test where two wireless Xbox 360 pads
        // each showed up as TWO InControl devices, controlling two
        // players per physical pad. Set ROUNDS_MULTIPAD_DEDUPE=0 to
        // disable (e.g. if you have a genuine Xbox One pad alongside
        // a 360 and want both to register).
        public const string EnableDedupeEnv = "ROUNDS_MULTIPAD_DEDUPE";

        internal static ManualLogSource Log;
        internal static bool DedupeEnabled;

        private void Awake()
        {
            Log = Logger;
            DedupeEnabled = Environment.GetEnvironmentVariable(EnableDedupeEnv) != "0";
            Log.LogInfo(
                "RoundsMultiPad awake — installing UnityInputDeviceManager forcer "
                + $"(dedupe={(DedupeEnabled ? "ON" : "OFF")})");
            try
            {
                var harmony = new Harmony(PluginGuid);
                var setupTarget = AccessTools.Method(typeof(InputManager), "SetupInternal");
                if (setupTarget == null)
                {
                    Log.LogError(
                        "Could not find InControl.InputManager.SetupInternal — InControl API drift?");
                    return;
                }
                var setupPostfix = AccessTools.Method(typeof(SetupInternalPatch), "Postfix");
                harmony.Patch(setupTarget, postfix: new HarmonyMethod(setupPostfix));
                Log.LogInfo("Patched InputManager.SetupInternal with postfix");

                var attachTarget = AccessTools.Method(
                    typeof(UnityInputDeviceManager), "AttachJoystickDevices");
                if (attachTarget == null)
                {
                    Log.LogError(
                        "Could not find UnityInputDeviceManager.AttachJoystickDevices — "
                        + "per-attach diagnostic pass disabled.");
                }
                else
                {
                    var attachPostfix = AccessTools.Method(
                        typeof(AttachJoystickDevicesPatch), "Postfix");
                    harmony.Patch(attachTarget, postfix: new HarmonyMethod(attachPostfix));
                    Log.LogInfo("Patched UnityInputDeviceManager.AttachJoystickDevices with postfix");
                }
            }
            catch (Exception e)
            {
                Log.LogError($"RoundsMultiPad failed to install patch: {e}");
            }
        }

        // Per-frame: poll each Unity joystick slot directly (Input.GetKey
        // "joystick N button M" — bypasses InControl entirely), and when
        // ANY joystick slot's button-0 transitions 0→1, dump button-0
        // state for every slot. The point is to expose whether wine
        // xinput is mirroring one physical pad's events onto multiple
        // Unity joystick slots: press button A on physical pad 1 only,
        // and if Unity reports button 0 down on BOTH joystick 1 AND
        // joystick 2, that's the mirror bug.
        // Rate-limited to one dump per ~250ms so holding a button
        // doesn't flood the log.
        private float _lastDumpTime = -1f;
        private bool[] _prevDown = new bool[16];

        private void Update()
        {
            try
            {
                if (Time.realtimeSinceStartup - _lastDumpTime < 0.25f) return;
                var names = UnityEngine.Input.GetJoystickNames();
                int n = names != null ? names.Length : 0;
                if (n == 0) return;
                bool anyTransition = false;
                bool[] nowDown = new bool[n];
                for (int i = 0; i < n && i < _prevDown.Length; i++)
                {
                    if (string.IsNullOrEmpty(names[i])) continue;
                    // Probe a wide range of joystick buttons (0..19).
                    bool down = false;
                    for (int b = 0; b < 20; b++)
                    {
                        var code = (UnityEngine.KeyCode)System.Enum.Parse(
                            typeof(UnityEngine.KeyCode), $"Joystick{i + 1}Button{b}", false);
                        if (UnityEngine.Input.GetKey(code)) { down = true; break; }
                    }
                    nowDown[i] = down;
                    if (down && !_prevDown[i]) anyTransition = true;
                    _prevDown[i] = down;
                }
                if (!anyTransition) return;
                _lastDumpTime = Time.realtimeSinceStartup;
                Log.LogInfo("[live-poll] BUTTON TRANSITION — Unity joystick slot states:");
                for (int i = 0; i < n; i++)
                {
                    var btns = new System.Text.StringBuilder();
                    for (int b = 0; b < 20; b++)
                    {
                        var code = (UnityEngine.KeyCode)System.Enum.Parse(
                            typeof(UnityEngine.KeyCode), $"Joystick{i + 1}Button{b}", false);
                        if (UnityEngine.Input.GetKey(code)) btns.Append($"B{b} ");
                    }
                    Log.LogInfo(
                        $"[live-poll]   joystick {i + 1} \"{names[i]}\" "
                        + $"down=[{btns.ToString().TrimEnd()}]");
                }
            }
            catch (Exception e)
            {
                Log.LogError($"RoundsMultiPad Update threw: {e}");
            }
        }
    }

    // Postfix InputManager.SetupInternal so that whenever InControl
    // finishes initialising — regardless of whether it picked the
    // native or XInput backend — a UnityInputDeviceManager is also
    // attached. AddDeviceManager is idempotent in our favour: it
    // logs and no-ops if the manager type is already registered.
    internal static class SetupInternalPatch
    {
        public static void Postfix(bool __result)
        {
            if (!__result)
            {
                return;
            }

            try
            {
                if (InputManager.HasDeviceManager<UnityInputDeviceManager>())
                {
                    RoundsMultiPadPlugin.Log.LogInfo(
                        "UnityInputDeviceManager already attached by InControl — nothing to do");
                    return;
                }

                RoundsMultiPadPlugin.Log.LogInfo(
                    "Native/XInput backend won the setup race; forcing UnityInputDeviceManager alongside it");
                InputManager.AddDeviceManager<UnityInputDeviceManager>();

                // Remove the NativeInputDeviceManager via reflection so
                // we don't end up with both managers enumerating the
                // same physical pads (which causes ROUNDS' PlayerAssigner
                // to fire OnDeviceAttached twice per pad → 2 player
                // slots spawn per physical pad). Set
                // ROUNDS_MULTIPAD_KEEP_NATIVE=1 to disable this removal.
                if (Environment.GetEnvironmentVariable("ROUNDS_MULTIPAD_KEEP_NATIVE") != "1")
                {
                    try
                    {
                        var dmField = AccessTools.Field(typeof(InputManager), "deviceManagers");
                        var dmList = dmField?.GetValue(null) as System.Collections.IList;
                        if (dmList == null)
                        {
                            RoundsMultiPadPlugin.Log.LogWarning(
                                "Could not find InputManager.deviceManagers list — native removal skipped");
                        }
                        else
                        {
                            int removed = 0;
                            for (int i = dmList.Count - 1; i >= 0; i--)
                            {
                                var dm = dmList[i];
                                if (dm == null) continue;
                                var name = dm.GetType().Name;
                                if (name == "NativeInputDeviceManager")
                                {
                                    RoundsMultiPadPlugin.Log.LogInfo(
                                        $"Removing NativeInputDeviceManager (index {i}) to suppress double-enumeration");
                                    dmList.RemoveAt(i);
                                    removed++;
                                }
                            }
                            RoundsMultiPadPlugin.Log.LogInfo(
                                $"Removed {removed} NativeInputDeviceManager instance(s); "
                                + $"deviceManagers.Count={dmList.Count}");
                        }
                    }
                    catch (Exception e)
                    {
                        RoundsMultiPadPlugin.Log.LogError(
                            $"NativeInputDeviceManager removal threw: {e}");
                    }
                }

                AttachJoystickDevicesPatch.MaybeDedupe("post-AddDeviceManager");
                DeviceIntrospection.DumpAll("post-AddDeviceManager");
            }
            catch (Exception e)
            {
                RoundsMultiPadPlugin.Log.LogError(
                    $"RoundsMultiPad postfix threw: {e}");
            }
        }
    }

    internal static class AttachJoystickDevicesPatch
    {
        public static void Postfix()
        {
            MaybeDedupe("post-AttachJoystickDevices");
            DeviceIntrospection.DumpAll("post-AttachJoystickDevices");
        }

        // Legacy heuristic, off by default. See EnableDedupeEnv.
        internal static void MaybeDedupe(string reason)
        {
            if (!RoundsMultiPadPlugin.DedupeEnabled)
            {
                return;
            }

            try
            {
                var unityDevices = new List<InputDevice>();
                foreach (var d in InputManager.Devices)
                {
                    if (d is UnityInputDevice)
                    {
                        unityDevices.Add(d);
                    }
                }

                bool hasXbox360 = unityDevices.Any(
                    d => d.Name != null && d.Name.IndexOf(
                        "Xbox 360", StringComparison.Ordinal) >= 0);
                if (!hasXbox360)
                {
                    return;
                }

                var duplicates = unityDevices.Where(
                    d => d.Name != null && d.Name.IndexOf(
                        "XBox One", StringComparison.Ordinal) >= 0).ToList();
                if (duplicates.Count == 0)
                {
                    return;
                }

                foreach (var dup in duplicates)
                {
                    RoundsMultiPadPlugin.Log.LogInfo(
                        $"[{reason}] detaching wine duplicate: name=\"{dup.Name}\" "
                        + $"sort={dup.SortOrder} (ROUNDS_MULTIPAD_DEDUPE=1 opt-in heuristic)");
                    InputManager.DetachDevice(dup);
                }
            }
            catch (Exception e)
            {
                RoundsMultiPadPlugin.Log.LogError(
                    $"RoundsMultiPad dedupe threw at {reason}: {e}");
            }
        }
    }

    // Heavy device-dump used to correlate Unity InControl devices
    // back to physical pads. For each UnityInputDevice we log:
    //   • the device Name + Meta + SortOrder + IsKnown flag
    //   • the (reflected) profile Name and Meta
    //   • the public JoystickId
    //   • the matching Unity-side joystick name (from
    //     Input.GetJoystickNames) at the same slot
    //   • per-analog: target enum, handle string, source
    //     UnityAnalogSource.AnalogIndex (or "?" for non-Unity
    //     sources) and the live ReadRawAnalogValue at log time
    //   • per-button: target enum, handle string, source
    //     UnityButtonSource.ButtonIndex and the live
    //     ReadRawButtonState at log time
    //
    // The live values let the user mash a single button or push
    // one stick, then read the log to find exactly which Unity
    // device saw it — names alone are not enough.
    internal static class DeviceIntrospection
    {
        // The shipped InControl fork has UnityInputDevice's profile
        // as a private field `profile` of type
        // UnityInputDeviceProfileBase (no Profile property). Reflect
        // it once.
        private static readonly FieldInfo ProfileField = typeof(UnityInputDevice)
            .GetField("profile", BindingFlags.NonPublic | BindingFlags.Instance);

        public static void DumpAll(string reason)
        {
            var log = RoundsMultiPadPlugin.Log;
            try
            {
                string[] unityNames = null;
                try { unityNames = Input.GetJoystickNames(); }
                catch (Exception e) { log.LogWarning($"GetJoystickNames threw: {e.Message}"); }

                if (unityNames != null)
                {
                    for (int i = 0; i < unityNames.Length; i++)
                    {
                        log.LogInfo(
                            $"[{reason}] Unity joystick slot {i + 1}: \"{unityNames[i]}\"");
                    }
                }

                int idx = 0;
                foreach (var dev in InputManager.Devices)
                {
                    idx++;
                    DumpDevice(reason, idx, dev, unityNames);
                }
                log.LogInfo($"[{reason}] InputManager.Devices.Count={idx}");
            }
            catch (Exception e)
            {
                log.LogError($"DeviceIntrospection.DumpAll threw at {reason}: {e}");
            }
        }

        private static void DumpDevice(string reason, int idx, InputDevice dev, string[] unityNames)
        {
            var log = RoundsMultiPadPlugin.Log;
            var unityDev = dev as UnityInputDevice;
            string typeName = dev.GetType().Name;
            int joystickId = 0;
            string profileName = null;
            string profileMeta = null;
            string unitySlotName = null;
            InputControlMapping[] analogs = null;
            InputControlMapping[] buttons = null;

            if (unityDev != null)
            {
                try { joystickId = unityDev.JoystickId; }
                catch { }
                if (joystickId >= 1 && unityNames != null && joystickId - 1 < unityNames.Length)
                {
                    unitySlotName = unityNames[joystickId - 1];
                }
                if (ProfileField != null)
                {
                    var p = ProfileField.GetValue(unityDev) as InputDeviceProfile;
                    if (p != null)
                    {
                        try { profileName = p.Name; } catch { }
                        try { profileMeta = p.Meta; } catch { }
                        try { analogs = p.AnalogMappings; } catch { }
                        try { buttons = p.ButtonMappings; } catch { }
                    }
                }
            }

            log.LogInfo(
                $"[{reason}] Device[{idx}] type={typeName} name=\"{dev.Name}\" "
                + $"meta=\"{dev.Meta}\" sort={dev.SortOrder} isKnown={dev.IsKnown} "
                + $"joystickId={joystickId} unitySlotName=\"{unitySlotName ?? "n/a"}\" "
                + $"profileName=\"{profileName ?? "n/a"}\" profileMeta=\"{profileMeta ?? "n/a"}\"");

            int analogCount = analogs != null ? analogs.Length : 0;
            int buttonCount = buttons != null ? buttons.Length : 0;
            log.LogInfo(
                $"[{reason}] Device[{idx}] analogs={analogCount} buttons={buttonCount}");

            for (int i = 0; i < analogCount; i++)
            {
                var m = analogs[i];
                int analogIndex = -1;
                string sourceType = m.Source != null ? m.Source.GetType().Name : "null";
                var unityAnalog = m.Source as UnityAnalogSource;
                if (unityAnalog != null) analogIndex = unityAnalog.AnalogIndex;

                float live = 0f;
                if (unityDev != null && analogIndex >= 0)
                {
                    try { live = unityDev.ReadRawAnalogValue(analogIndex); }
                    catch { }
                }
                log.LogInfo(
                    $"[{reason}] Device[{idx}] analog[{i}] target={m.Target} "
                    + $"handle=\"{m.Handle}\" sourceType={sourceType} "
                    + $"analogIndex={(analogIndex >= 0 ? analogIndex.ToString() : "?")} "
                    + $"live={live:F3}");
            }

            for (int i = 0; i < buttonCount; i++)
            {
                var m = buttons[i];
                int buttonIndex = -1;
                string sourceType = m.Source != null ? m.Source.GetType().Name : "null";
                var unityButton = m.Source as UnityButtonSource;
                if (unityButton != null) buttonIndex = unityButton.ButtonIndex;

                bool live = false;
                if (unityDev != null && buttonIndex >= 0)
                {
                    try { live = unityDev.ReadRawButtonState(buttonIndex); }
                    catch { }
                }
                log.LogInfo(
                    $"[{reason}] Device[{idx}] button[{i}] target={m.Target} "
                    + $"handle=\"{m.Handle}\" sourceType={sourceType} "
                    + $"buttonIndex={(buttonIndex >= 0 ? buttonIndex.ToString() : "?")} "
                    + $"live={(live ? "1" : "0")}");
            }
        }
    }
}
