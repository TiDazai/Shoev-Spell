using System.Globalization;
using System.Text;

namespace ShoevSpell.Windows;

internal sealed class SpellEngine
{
    private static readonly HashSet<uint> ResetKeys = [0x08, 0x2E, 0x25, 0x26, 0x27, 0x28, 0x21, 0x22, 0x23, 0x24, 0x09, 0x1B];
    private static readonly HashSet<string> Excluded = new(StringComparer.OrdinalIgnoreCase) { "Shoev Spell", "Shoev Switcher", "WindowsTerminal", "powershell", "pwsh", "cmd", "Code", "devenv", "KeePass", "1Password" };
    private readonly Lexicon lexicon;
    private string word = "";
    private string phrase = "";
    private nint activeWindow;
    internal event Action<string, string, string>? Corrected;

    internal SpellEngine(Lexicon lexicon) => this.lexicon = lexicon;

    internal bool HandleKey(KeyEvent key)
    {
        var foreground = NativeMethods.GetForegroundWindow();
        if (foreground != activeWindow) { Reset(); activeWindow = foreground; }
        var processName = NativeMethods.ForegroundProcessName();
        if (!SettingsStore.GetBool("Enabled", true) || Excluded.Contains(processName)
            || SettingsStore.GetExclusions().Contains(processName, StringComparer.OrdinalIgnoreCase)
            || NativeMethods.FocusedControlIsPassword()) { Reset(); return false; }
        if ((Control.ModifierKeys & (Keys.Control | Keys.Alt)) != 0 || key.VirtualKey is 0x5B or 0x5C) { Reset(); return false; }
        if (ResetKeys.Contains(key.VirtualKey)) { Reset(); return false; }

        var text = key.Text();
        if (text.Length == 0) return false;
        if (text.All(char.IsLetter))
        {
            if (SettingsStore.GetBool("Capitalization", true) && word.Length == 0 && ShouldCapitalize(phrase) && text.Any(char.IsLower))
            {
                var upper = text.ToUpper(CultureInfo.CurrentCulture);
                word += upper; phrase += upper;
                NativeMethods.ReplaceText(0, upper, "");
                return true;
            }
            word += text; phrase += text;
            if (word.Length > 32 || phrase.Length > 500) Reset();
            return false;
        }

        if (text is " " or "\r" or "\n" || text.All(c => ",.;:!?…".Contains(c)))
            return Finish(text);

        Reset();
        return false;
    }

    private bool Finish(string delimiter)
    {
        var original = phrase;
        var replacement = phrase;
        string? correctedWord = null;
        if (word.Length > 0 && SettingsStore.GetBool("Correction", true) && CorrectionEngine.Find(word, lexicon) is { } corrected)
        {
            correctedWord = corrected;
            replacement = replacement[..^word.Length] + corrected;
        }
        if (SettingsStore.GetBool("Punctuation", true)) replacement = RussianPunctuation.Punctuate(replacement);
        if (delimiter is "\r" or "\n" && replacement.Length > 0 && SettingsStore.GetBool("Punctuation", true) && !".!?…:;".Contains(replacement[^1]))
            replacement += RussianPunctuation.TerminalMark(replacement);

        if (replacement != original && original.Length > 0)
        {
            NativeMethods.ReplaceText(original.Length, replacement, delimiter);
            if (correctedWord is not null) Corrected?.Invoke(word, correctedWord, NativeMethods.ForegroundProcessName());
            if (delimiter is "\r" or "\n") Reset(); else { phrase = replacement + delimiter; word = ""; }
            return true;
        }
        if (delimiter is "\r" or "\n") Reset(); else { phrase += delimiter; word = ""; }
        return false;
    }

    private static bool ShouldCapitalize(string prefix)
    {
        var trimmed = prefix.TrimEnd(' ', '\t');
        return trimmed.Length == 0 || "\r\n.!?…«„“\"".Contains(trimmed[^1]);
    }
    private void Reset() { word = ""; phrase = ""; }
}

internal static class CorrectionEngine
{
    private const string English = "abcdefghijklmnopqrstuvwxyz";
    private const string Russian = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя";
    internal static string? Find(string original, Lexicon lexicon)
    {
        if (original.Length is < 3 or > 32 || !original.All(char.IsLetter) || original.Equals("shoev", StringComparison.OrdinalIgnoreCase)) return null;
        var lower = original.ToLowerInvariant();
        var language = lower.Any(c => c is >= 'а' and <= 'я' or 'ё') ? 1 : lower.All(c => c is >= 'a' and <= 'z') ? 0 : -1;
        if (language < 0) return null;
        var originalScore = lexicon.Score(lower, language);
        if (originalScore >= 250) return null;
        var candidates = Edits(lower, language == 0 ? English : Russian)
            .Select(value => (value, score: lexicon.Score(value, language))).Where(x => x.score is not null)
            .OrderByDescending(x => x.score).ThenBy(x => x.value, StringComparer.Ordinal).Take(2).ToArray();
        if (candidates.Length == 0 || candidates[0].score < 250 || candidates.Length > 1 && candidates[0].score - candidates[1].score < 25) return null;
        if (originalScore is not null && !(originalScore < 180 && candidates[0].score >= 400 && candidates[0].score - originalScore >= 200)) return null;
        var result = candidates[0].value;
        if (original.All(char.IsUpper)) return result.ToUpperInvariant();
        return char.IsUpper(original[0]) ? char.ToUpper(result[0], CultureInfo.CurrentCulture) + result[1..] : result;
    }

    private static HashSet<string> Edits(string word, string alphabet)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        for (var i = 0; i < word.Length; i++)
        {
            result.Add(word.Remove(i, 1));
            if (i + 1 < word.Length) { var chars = word.ToCharArray(); (chars[i], chars[i + 1]) = (chars[i + 1], chars[i]); result.Add(new string(chars)); }
            foreach (var c in alphabet) if (c != word[i]) result.Add(word[..i] + c + word[(i + 1)..]);
        }
        for (var i = 0; i <= word.Length; i++) foreach (var c in alphabet) result.Add(word[..i] + c + word[i..]);
        result.Remove(word); return result;
    }
}

internal static class RussianPunctuation
{
    private static readonly HashSet<string> Intro = new(StringComparer.OrdinalIgnoreCase) { "конечно", "возможно", "вероятно", "кажется", "наверное", "например", "кстати", "итак", "следовательно", "пожалуй", "разумеется", "безусловно" };
    private static readonly HashSet<string> Conjunctions = new(StringComparer.OrdinalIgnoreCase) { "а", "но", "зато", "однако", "что", "чтобы", "если", "когда", "хотя", "поскольку", "где", "куда", "откуда" };
    internal static string Punctuate(string text)
    {
        if (!text.Any(c => c is >= 'А' and <= 'я' or 'Ё' or 'ё') || text.IndexOfAny(['@', '#', '/', ':', '\\']) >= 0) return text;
        var words = System.Text.RegularExpressions.Regex.Matches(text, "[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)*");
        var offsets = new HashSet<int>();
        for (var i = 1; i < words.Count; i++) if (Conjunctions.Contains(words[i].Value)) offsets.Add(words[i - 1].Index + words[i - 1].Length);
        for (var i = 0; i < words.Count; i++) if (Intro.Contains(words[i].Value)) { if (i > 0) offsets.Add(words[i - 1].Index + words[i - 1].Length); if (i + 1 < words.Count) offsets.Add(words[i].Index + words[i].Length); }
        var result = new StringBuilder(text);
        foreach (var offset in offsets.OrderDescending()) if (offset < result.Length && result[offset] != ',' && (offset == 0 || result[offset - 1] != ',')) result.Insert(offset, ',');
        return result.ToString();
    }
    internal static char TerminalMark(string text)
    {
        var first = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.ToLowerInvariant();
        return first is "кто" or "что" or "где" or "куда" or "когда" or "как" or "зачем" or "почему" or "сколько" ? '?' : '.';
    }
}
