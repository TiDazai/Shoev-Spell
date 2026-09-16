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
    private readonly bool testMode;
    internal event Action<string, string, string>? Corrected;

    internal SpellEngine(Lexicon lexicon, bool testMode = false) { this.lexicon = lexicon; this.testMode = testMode; }

    internal bool HandleKey(KeyEvent key)
    {
        if (key.FromShoevSwitcher) { ObserveExternal(key); return false; }
        var foreground = NativeMethods.GetForegroundWindow();
        if (foreground != activeWindow) { Reset(); activeWindow = foreground; }
        var processName = NativeMethods.ForegroundProcessName();
        if (!Setting("Enabled", true) || (!testMode && (Excluded.Contains(processName)
            || SettingsStore.GetExclusions().Contains(processName, StringComparer.OrdinalIgnoreCase)))
            || NativeMethods.FocusedControlIsPassword()) { Reset(); return false; }
        if ((Control.ModifierKeys & (Keys.Control | Keys.Alt)) != 0 || key.VirtualKey is 0x5B or 0x5C) { Reset(); return false; }
        if (ResetKeys.Contains(key.VirtualKey)) { Reset(); return false; }

        var text = key.Text();
        if (text.Length == 0) return false;
        if (text.All(char.IsLetter))
        {
            if (Setting("Capitalization", true) && word.Length == 0 && ShouldCapitalize(phrase) && text.Any(char.IsLower))
            {
                var upper = text.ToUpper(CultureInfo.CurrentCulture);
                if (NativeMethods.ReplaceText(0, upper, "")) { word += upper; phrase += upper; return true; }
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

    private void ObserveExternal(KeyEvent key)
    {
        if (ResetKeys.Contains(key.VirtualKey)) { Reset(); return; }
        var text = key.Text();
        if (text.Length == 0) return;
        if (text.All(char.IsLetter))
        {
            word += text; phrase += text;
            if (word.Length > 32 || phrase.Length > 500) Reset();
            return;
        }
        if (text == " ") { phrase += text; word = ""; return; }
        if (text is "\r" or "\n") { Reset(); return; }
        if (text.All(c => ",.;:!?…".Contains(c))) { phrase += text; word = ""; return; }
        Reset();
    }

    private bool Finish(string delimiter)
    {
        var original = phrase;
        var replacement = phrase;
        string? correctedWord = null;
        if (word.Length > 0 && Setting("Correction", true) && CorrectionEngine.Find(word, lexicon) is { } corrected)
        {
            correctedWord = corrected;
            replacement = replacement[..^word.Length] + corrected;
        }
        if (Setting("Punctuation", true)) replacement = RussianPunctuation.Punctuate(replacement);
        if (delimiter is "\r" or "\n" && replacement.Length > 0 && Setting("Punctuation", true) && !".!?…:;".Contains(replacement[^1]))
            replacement += RussianPunctuation.TerminalMark(replacement);

        if (replacement != original && original.Length > 0)
        {
            if (!NativeMethods.ReplaceText(original.Length, replacement, delimiter))
            {
                if (delimiter is "\r" or "\n") Reset(); else { phrase += delimiter; word = ""; }
                return false;
            }
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
    private bool Setting(string key, bool fallback) => testMode || SettingsStore.GetBool(key, fallback);
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
    private sealed record Token(string Value, int Index, int Length, bool Capitalized);
    private static readonly HashSet<string> Adversative = new() { "а", "но", "зато", "однако" };
    private static readonly HashSet<string> Subordinate = new() { "что", "чтобы", "если", "когда", "пока", "хотя", "поскольку", "где", "куда", "откуда", "который", "которая", "которое", "которые", "которого", "которой", "которых", "которому", "которым", "которыми" };
    private static readonly HashSet<string> IntroWords = new() { "безусловно", "бесспорно", "вероятно", "видимо", "во-первых", "во-вторых", "во-третьих", "возможно", "впрочем", "естественно", "итак", "кажется", "конечно", "короче", "кстати", "наверное", "наконец", "например", "наоборот", "несомненно", "очевидно", "пожалуй", "по-видимому", "по-моему", "по-твоему", "разумеется", "следовательно", "словом" };
    private static readonly string[][] IntroPhrases = [
        ["без", "сомнения"], ["быть", "может"], ["в", "общем"], ["в", "самом", "деле"], ["в", "частности"],
        ["во", "всяком", "случае"], ["другими", "словами"], ["иначе", "говоря"], ["к", "сожалению"],
        ["к", "счастью"], ["между", "прочим"], ["может", "быть"], ["одним", "словом"], ["по", "сути"],
        ["само", "собой"], ["собственно", "говоря"], ["строго", "говоря"], ["таким", "образом"], ["честно", "говоря"]
    ];
    private static readonly string[][] CompoundConjunctions = [
        ["благодаря", "тому", "что"], ["в", "то", "время", "как"], ["ввиду", "того", "что"], ["для", "того", "чтобы"],
        ["до", "того", "как"], ["из-за", "того", "что"], ["как", "будто"], ["несмотря", "на", "то", "что"],
        ["перед", "тем", "как"], ["по", "мере", "того", "как"], ["после", "того", "как"], ["потому", "что"],
        ["с", "тем", "чтобы"], ["с", "тех", "пор", "как"], ["так", "как"], ["так", "что"]
    ];
    private static readonly HashSet<string> Addresses = new() { "бабушка", "брат", "братья", "господа", "граждане", "дамы", "дедушка", "доктор", "друзья", "друг", "коллега", "коллеги", "мама", "мам", "мужчина", "папа", "пап", "подруга", "ребята", "сестра", "товарищи", "уважаемые", "уважаемый", "уважаемая", "учитель" };
    private static readonly HashSet<string> Imperatives = new() { "будем", "будьте", "возьми", "возьмите", "давай", "давайте", "дай", "дайте", "запомни", "запомните", "напиши", "напишите", "позвони", "позвоните", "помоги", "помогите", "послушай", "послушайте", "посмотри", "посмотрите", "приходи", "приходите", "скажи", "скажите", "сделай", "сделайте" };
    private static readonly HashSet<string> Questions = new() { "кто", "что", "где", "куда", "откуда", "когда", "как", "зачем", "почему", "сколько", "чей", "чья", "чьё", "чьи", "какой", "какая", "какое", "какие" };

    internal static string Punctuate(string text)
    {
        if (text.Length > 500 || !text.Any(c => c is >= 'А' and <= 'я' or 'Ё' or 'ё') || text.IndexOfAny(['@', '#', '/', ':', '\\']) >= 0) return text;
        var words = System.Text.RegularExpressions.Regex.Matches(text, "[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)*")
            .Select(x => new Token(x.Value.ToLowerInvariant(), x.Index, x.Length, char.IsUpper(x.Value[0]))).ToArray();
        if (words.Length < 2) return text;
        var offsets = new HashSet<int>();
        AddClauseCommas(words, text, offsets); AddIntroductoryCommas(words, text, offsets); AddRepeatedConjunctions(words, text, offsets);
        AddGreetingAndAddress(words, text, offsets); AddExplanatory(words, text, offsets);
        var result = new StringBuilder(text);
        foreach (var offset in offsets.OrderDescending()) result.Insert(offset, ',');
        return result.ToString();
    }

    private static void AddClauseCommas(Token[] words, string text, HashSet<int> offsets)
    {
        for (var i = 1; i < words.Length; i++)
        {
            if (Adversative.Contains(words[i].Value)) { Before(i, words, text, offsets); continue; }
            var start = CompoundStart(i, words) ?? i;
            if (start == i && !Subordinate.Contains(words[i].Value)) continue;
            if (words[i].Value == "что" && i + 1 < words.Length && new[] { "бы", "ли", "за" }.Contains(words[i + 1].Value)) continue;
            if (words[i].Value == "что" && new[] { "за", "про", "ни" }.Contains(words[i - 1].Value)) continue;
            if (start > 0 && new[] { "даже", "только", "лишь", "особенно" }.Contains(words[start - 1].Value)) start--;
            if (start > 0) Before(start, words, text, offsets);
        }
    }
    private static int? CompoundStart(int end, Token[] words)
    {
        foreach (var phrase in CompoundConjunctions.OrderByDescending(x => x.Length))
        {
            var start = end + 1 - phrase.Length;
            if (start >= 0 && words.Skip(start).Take(phrase.Length).Select(x => x.Value).SequenceEqual(phrase)) return start;
        }
        return null;
    }
    private static void AddIntroductoryCommas(Token[] words, string text, HashSet<int> offsets)
    {
        for (var i = 0; i < words.Length; i++) if (IntroWords.Contains(words[i].Value)) { if (i > 0) Before(i, words, text, offsets); if (i + 1 < words.Length) After(i, words, text, offsets); }
        foreach (var phrase in IntroPhrases)
            for (var start = 0; start + phrase.Length <= words.Length; start++)
                if (words.Skip(start).Take(phrase.Length).Select(x => x.Value).SequenceEqual(phrase)) { if (start > 0) Before(start, words, text, offsets); if (start + phrase.Length < words.Length) After(start + phrase.Length - 1, words, text, offsets); }
    }
    private static void AddRepeatedConjunctions(Token[] words, string text, HashSet<int> offsets)
    {
        foreach (var conjunction in new[] { "и", "или", "либо" })
        {
            var occurrences = Enumerable.Range(0, words.Length).Where(i => words[i].Value == conjunction).ToArray();
            if (occurrences.Length > 1 && occurrences[0] > 0) foreach (var index in occurrences.Skip(1)) Before(index, words, text, offsets);
        }
        var first = Array.FindIndex(words, x => x.Value == "как");
        if (first >= 0) { var second = Array.FindIndex(words, first + 1, x => x.Value == "так"); if (second > first) Before(second, words, text, offsets); }
    }
    private static void AddGreetingAndAddress(Token[] words, string text, HashSet<int> offsets)
    {
        if (new[] { "привет", "здравствуй", "здравствуйте" }.Contains(words[0].Value) && words.Length > 1) After(0, words, text, offsets);
        if (words[0].Value == "добрый" && words.Length > 2 && new[] { "день", "вечер" }.Contains(words[1].Value)) After(1, words, text, offsets);
        if (Addresses.Contains(words[0].Value) && IsImperative(words[1].Value)) After(0, words, text, offsets);
        if (new[] { "спасибо", "извини", "извините", "простите", "пожалуйста" }.Contains(words[0].Value)) After(0, words, text, offsets);
        if (words.Length > 2 && words[0].Capitalized && words[1].Capitalized && IsImperative(words[2].Value)) After(1, words, text, offsets);
        else if (words[0].Capitalized && IsImperative(words[1].Value)) After(0, words, text, offsets);
    }
    private static void AddExplanatory(Token[] words, string text, HashSet<int> offsets)
    {
        foreach (var phrase in new[] { new[] { "то", "есть" }, new[] { "а", "именно" }, new[] { "в", "том", "числе" } })
            for (var start = 1; start + phrase.Length <= words.Length; start++) if (words.Skip(start).Take(phrase.Length).Select(x => x.Value).SequenceEqual(phrase)) Before(start, words, text, offsets);
    }
    private static bool IsImperative(string value) => Imperatives.Contains(value) || value.EndsWith("йте") || value.EndsWith("итесь") || value.EndsWith("айте") || value.EndsWith("яйте");
    private static void Before(int index, Token[] words, string text, HashSet<int> offsets) => Add(words[index - 1].Index + words[index - 1].Length, text, offsets);
    private static void After(int index, Token[] words, string text, HashSet<int> offsets) => Add(words[index].Index + words[index].Length, text, offsets);
    private static void Add(int offset, string text, HashSet<int> offsets)
    {
        var cursor = offset; while (cursor < text.Length && char.IsWhiteSpace(text[cursor])) cursor++;
        if (cursor < text.Length && ",;:—–-.!?…".Contains(text[cursor])) return;
        if (offset > 0 && ",;:—–-".Contains(text[offset - 1])) return;
        offsets.Add(offset);
    }
    internal static char TerminalMark(string text)
    {
        var first = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.ToLowerInvariant();
        return first is not null && (Questions.Contains(first) || text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("ли", StringComparer.OrdinalIgnoreCase)) ? '?' : '.';
    }
}
