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
//   then works unchanged — no per-frame synthesis, no fake device
//   subclass.

using System;
using System.Reflection;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using InControl;

namespace RoundsMultiPad
{
    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public class RoundsMultiPadPlugin : BaseUnityPlugin
    {
        public const string PluginGuid = "strom.rounds.multipad";
        public const string PluginName = "RoundsMultiPad";
        public const string PluginVersion = "1.0.0";

        internal static ManualLogSource Log;

        private void Awake()
        {
            Log = Logger;
            Log.LogInfo("RoundsMultiPad awake — installing UnityInputDeviceManager forcer");
            try
            {
                var harmony = new Harmony(PluginGuid);
                var target = AccessTools.Method(typeof(InputManager), "SetupInternal");
                if (target == null)
                {
                    Log.LogError(
                        "Could not find InControl.InputManager.SetupInternal — InControl API drift?");
                    return;
                }
                var postfix = AccessTools.Method(typeof(SetupInternalPatch), "Postfix");
                harmony.Patch(target, postfix: new HarmonyMethod(postfix));
                Log.LogInfo("Patched InputManager.SetupInternal with postfix");
            }
            catch (Exception e)
            {
                Log.LogError($"RoundsMultiPad failed to install patch: {e}");
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
            // __result == false means SetupInternal short-circuited
            // because InputManager was already set up. The first
            // call (from InControlManager.OnEnable) is the one that
            // matters; bail out early on subsequent re-entries.
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

                int count = 0;
                foreach (var d in InputManager.Devices)
                {
                    count++;
                    RoundsMultiPadPlugin.Log.LogInfo(
                        $"  device[{count}] {d.GetType().Name} name=\"{d.Name}\" sort={d.SortOrder}");
                }
                RoundsMultiPadPlugin.Log.LogInfo(
                    $"InputManager.Devices.Count={count} after forced attach");
            }
            catch (Exception e)
            {
                RoundsMultiPadPlugin.Log.LogError(
                    $"RoundsMultiPad postfix threw: {e}");
            }
        }
    }
}
