namespace Prism.Core.Hotkeys;

/// <summary>
/// Keyboard shortcut: one key + modifier flags.
/// Windows defaults use Control+Alt (Ctrl+Alt+T) — same intent as macOS Control+Option.
/// </summary>
public sealed class HotkeyChord : IEquatable<HotkeyChord>
{
    [Flags]
    public enum Modifiers : byte
    {
        None = 0,
        Control = 1 << 0,
        Alt = 1 << 1,
        Shift = 1 << 2,
        Win = 1 << 3,
    }

    public int VirtualKey { get; init; }
    public Modifiers Mods { get; init; }

    public static HotkeyChord TranslateOnlyDefault { get; } = new()
    {
        VirtualKey = 0x54, // T
        Mods = Modifiers.Control | Modifiers.Alt,
    };

    public static HotkeyChord TranslateAndSendDefault { get; } = new()
    {
        VirtualKey = 0x0D, // Enter
        Mods = Modifiers.Control | Modifiers.Alt,
    };

    public static HotkeyChord PopupDefault { get; } = new()
    {
        VirtualKey = 0x59, // Y
        Mods = Modifiers.Control | Modifiers.Alt,
    };

    public bool IsReturnKey => VirtualKey is 0x0D or 0x6C; // VK_RETURN / VK_SEPARATOR (numpad enter)

    public bool IsValid => Mods != Modifiers.None;

    public bool Matches(int virtualKey, Modifiers present)
    {
        var keyMatches = IsReturnKey
            ? virtualKey is 0x0D or 0x6C
            : virtualKey == VirtualKey;
        return keyMatches && present == Mods;
    }

    public string DisplayString
    {
        get
        {
            var parts = new List<string>();
            if (Mods.HasFlag(Modifiers.Control)) parts.Add("Ctrl");
            if (Mods.HasFlag(Modifiers.Alt)) parts.Add("Alt");
            if (Mods.HasFlag(Modifiers.Shift)) parts.Add("Shift");
            if (Mods.HasFlag(Modifiers.Win)) parts.Add("Win");
            parts.Add(KeyName(VirtualKey));
            return string.Join("+", parts);
        }
    }

    public static string KeyName(int virtualKey) => virtualKey switch
    {
        0x0D or 0x6C => "Enter",
        0x20 => "Space",
        0x09 => "Tab",
        0x08 => "Backspace",
        0x2E => "Delete",
        0x1B => "Esc",
        0x25 => "Left",
        0x27 => "Right",
        0x26 => "Up",
        0x28 => "Down",
        >= 0x70 and <= 0x7B => $"F{virtualKey - 0x6F}",
        >= 0x30 and <= 0x39 => ((char)virtualKey).ToString(),
        >= 0x41 and <= 0x5A => ((char)virtualKey).ToString(),
        _ => $"Key{virtualKey}",
    };

    public bool Equals(HotkeyChord? other) =>
        other is not null && VirtualKey == other.VirtualKey && Mods == other.Mods;

    public override bool Equals(object? obj) => Equals(obj as HotkeyChord);

    public override int GetHashCode() => HashCode.Combine(VirtualKey, Mods);
}
