using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace ShoevSpell.Windows;

internal static class NativeMethods
{
    internal const int WhKeyboardLl = 13;
    internal const int WmKeyDown = 0x0100;
    internal const int WmSysKeyDown = 0x0104;
    internal const uint LlkhfInjected = 0x10;
    internal const uint InputKeyboard = 1;
    internal const uint KeyeventfKeyup = 0x0002;
    internal const uint KeyeventfUnicode = 0x0004;
    internal const ushort VkBack = 0x08;
    internal static readonly nuint SelfInputMarker = unchecked((nuint)0x53484F455653504CUL);
    internal static readonly nuint SwitcherInputMarker = unchecked((nuint)0x53484F4556535749UL);
    internal const uint GuiCaretBlinking = 1;
    internal const uint EmGetPasswordChar = 0x00D2;
    internal const uint SmtoAbortIfHung = 0x0002;

    internal delegate nint HookProc(int code, nint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    internal struct KbdLlHookStruct { internal uint vkCode, scanCode, flags, time; internal nuint extraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct Input { internal uint type; internal InputUnion data; }
    [StructLayout(LayoutKind.Explicit)]
    internal struct InputUnion { [FieldOffset(0)] internal MouseInput mouse; [FieldOffset(0)] internal KeybdInput keyboard; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct MouseInput { internal int dx, dy; internal uint mouseData, flags, time; internal nuint extraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct KeybdInput { internal ushort virtualKey, scanCode; internal uint flags, time; internal nuint extraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct GuiThreadInfo
    {
        internal uint size, flags;
        internal nint active, focus, capture, menuOwner, moveSize, caret;
        internal int left, top, right, bottom;
    }

    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SetWindowsHookEx(int id, HookProc proc, nint module, uint threadId);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);
    [DllImport("kernel32.dll")] internal static extern nint GetModuleHandle(string? name);
    [DllImport("user32.dll")] internal static extern bool GetKeyboardState(byte[] state);
    [DllImport("user32.dll")] internal static extern nint GetKeyboardLayout(uint threadId);
    [DllImport("user32.dll")] internal static extern int ToUnicodeEx(uint vk, uint scan, byte[] state, [Out] StringBuilder buffer, int capacity, uint flags, nint layout);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] internal static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] internal static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);
    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SendMessageTimeout(nint window, uint message, nint wParam, nint lParam, uint flags, uint timeout, out nint result);

    internal static bool FocusedControlIsPassword()
    {
        var info = new GuiThreadInfo { size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        GetWindowThreadProcessId(GetForegroundWindow(), out _);
        if (!GetGUIThreadInfo(0, ref info) || info.focus == 0) return false;
        return SendMessageTimeout(info.focus, EmGetPasswordChar, 0, 0, SmtoAbortIfHung, 50, out var result) != 0 && result != 0;
    }

    internal static string ForegroundProcessName()
    {
        GetWindowThreadProcessId(GetForegroundWindow(), out var pid);
        try { return Process.GetProcessById((int)pid).ProcessName; } catch { return string.Empty; }
    }

    internal static bool ReplaceText(int deleteUtf16Units, string replacement, string delimiter)
    {
        var inputs = new List<Input>((deleteUtf16Units + replacement.Length + delimiter.Length) * 2);
        for (var i = 0; i < deleteUtf16Units; i++) AddVirtualKey(inputs, VkBack);
        foreach (var unit in (replacement + delimiter).AsSpan()) AddUnicode(inputs, unit);
        return inputs.Count == 0 || SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<Input>()) == inputs.Count;
    }

    internal static bool SendTestText(string value)
    {
        var inputs = new List<Input>(value.Length * 2);
        foreach (var unit in value.AsSpan())
        {
            inputs.Add(NewKeyboard(0, unit, KeyeventfUnicode, 0x54455354));
            inputs.Add(NewKeyboard(0, unit, KeyeventfUnicode | KeyeventfKeyup, 0x54455354));
        }
        return SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<Input>()) == inputs.Count;
    }

    private static void AddVirtualKey(List<Input> list, ushort key)
    {
        list.Add(NewKeyboard(key, 0, 0));
        list.Add(NewKeyboard(key, 0, KeyeventfKeyup));
    }

    private static void AddUnicode(List<Input> list, char unit)
    {
        list.Add(NewKeyboard(0, unit, KeyeventfUnicode));
        list.Add(NewKeyboard(0, unit, KeyeventfUnicode | KeyeventfKeyup));
    }

    private static Input NewKeyboard(ushort key, ushort scan, uint flags, nuint? marker = null) => new()
    {
        type = InputKeyboard,
        data = new InputUnion { keyboard = new KeybdInput { virtualKey = key, scanCode = scan, flags = flags, extraInfo = marker ?? SelfInputMarker } }
    };
}

internal sealed class KeyboardHook : IDisposable
{
    private readonly Func<KeyEvent, bool> handler;
    private readonly NativeMethods.HookProc callback;
    private nint hook;

    internal KeyboardHook(Func<KeyEvent, bool> handler) { this.handler = handler; callback = HookCallback; }
    internal void Start()
    {
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule!;
        hook = NativeMethods.SetWindowsHookEx(NativeMethods.WhKeyboardLl, callback, NativeMethods.GetModuleHandle(module.ModuleName), 0);
        if (hook == 0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    private nint HookCallback(int code, nint message, nint data)
    {
        if (code >= 0 && (message == NativeMethods.WmKeyDown || message == NativeMethods.WmSysKeyDown))
        {
            var raw = Marshal.PtrToStructure<NativeMethods.KbdLlHookStruct>(data);
            if (raw.extraInfo == NativeMethods.SwitcherInputMarker)
            {
                handler(new KeyEvent(raw.vkCode, raw.scanCode, true));
                return NativeMethods.CallNextHookEx(hook, code, message, data);
            }
            if (raw.extraInfo != NativeMethods.SelfInputMarker && handler(new KeyEvent(raw.vkCode, raw.scanCode, false))) return 1;
        }
        return NativeMethods.CallNextHookEx(hook, code, message, data);
    }
    public void Dispose() { if (hook != 0) NativeMethods.UnhookWindowsHookEx(hook); hook = 0; }
}

internal readonly record struct KeyEvent(uint VirtualKey, uint ScanCode, bool FromShoevSwitcher = false)
{
    internal string Text()
    {
        if (VirtualKey == 0xE7 && ScanCode > 0) return ((char)ScanCode).ToString();
        var state = new byte[256];
        if (!NativeMethods.GetKeyboardState(state)) return string.Empty;
        if (VirtualKey < state.Length) state[VirtualKey] |= 0x80;
        var foreground = NativeMethods.GetForegroundWindow();
        var thread = NativeMethods.GetWindowThreadProcessId(foreground, out _);
        var buffer = new StringBuilder(8);
        var count = NativeMethods.ToUnicodeEx(VirtualKey, ScanCode, state, buffer, buffer.Capacity, 0, NativeMethods.GetKeyboardLayout(thread));
        return count > 0 ? buffer.ToString(0, count) : string.Empty;
    }
}
