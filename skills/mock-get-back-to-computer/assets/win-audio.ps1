# win-audio.ps1 — system output volume and mute for the Windows alarm scripts.
# Dot-source it; it defines the [GbAudio] type, or throws if it cannot.
#
# Windows has no built-in command for the master volume, so this talks to the
# Core Audio API (the part of Windows that owns the default speaker's level)
# through a small piece of C#. Levels are 0-100, like the Mac scripts.
#
# UNTESTED — written without a Windows machine. If Add-Type fails here, the
# alarm runs without managing volume; see "Windows" in SKILL.md.

if (-not ('GbAudio' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    // Every method is declared, even unused ones: COM finds them by position.
    // PreserveSig keeps the raw HRESULT return, which the code below checks.
    [PreserveSig] int RegisterControlChangeNotify(IntPtr p);
    [PreserveSig] int UnregisterControlChangeNotify(IntPtr p);
    [PreserveSig] int GetChannelCount(out uint n);
    [PreserveSig] int SetMasterVolumeLevel(float db, ref Guid ctx);
    [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
    [PreserveSig] int GetMasterVolumeLevel(out float db);
    [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
    [PreserveSig] int SetChannelVolumeLevel(uint ch, float db, ref Guid ctx);
    [PreserveSig] int SetChannelVolumeLevelScalar(uint ch, float level, ref Guid ctx);
    [PreserveSig] int GetChannelVolumeLevel(uint ch, out float db);
    [PreserveSig] int GetChannelVolumeLevelScalar(uint ch, out float level);
    [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
    [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
                               [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject { }

public static class GbAudio {
    static IAudioEndpointVolume Endpoint() {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev;
        Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0 /* render */, 1 /* multimedia */, out dev));
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object o;
        Marshal.ThrowExceptionForHR(dev.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out o));
        return (IAudioEndpointVolume)o;
    }

    public static int GetVolume() {
        float v;
        Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out v));
        return (int)Math.Round(v * 100);
    }

    public static void SetVolume(int level) {
        Guid ctx = Guid.Empty;
        float v = Math.Max(0, Math.Min(100, level)) / 100f;
        Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(v, ref ctx));
    }

    public static bool GetMute() {
        bool m;
        Marshal.ThrowExceptionForHR(Endpoint().GetMute(out m));
        return m;
    }

    public static void SetMute(bool mute) {
        Guid ctx = Guid.Empty;
        Marshal.ThrowExceptionForHR(Endpoint().SetMute(mute, ref ctx));
    }
}
'@
}
