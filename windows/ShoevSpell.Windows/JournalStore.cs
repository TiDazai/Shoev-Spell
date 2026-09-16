using System.Text.Json;

namespace ShoevSpell.Windows;

internal sealed record JournalEntry(DateTime Time, string Application, string Original, string Replacement);

internal sealed class JournalStore
{
    private readonly string path = Path.Combine(SettingsStore.DirectoryPath, "corrections.jsonl");
    private readonly object gate = new();

    internal void Record(string original, string replacement, string application)
    {
        if (!SettingsStore.GetBool("Journal", true)) return;
        lock (gate)
        {
            Directory.CreateDirectory(SettingsStore.DirectoryPath);
            File.AppendAllText(path, JsonSerializer.Serialize(new JournalEntry(DateTime.Now, application, original, replacement)) + Environment.NewLine);
        }
    }

    internal List<JournalEntry> Read()
    {
        lock (gate)
        {
            if (!File.Exists(path)) return [];
            return File.ReadLines(path).Select(line => { try { return JsonSerializer.Deserialize<JournalEntry>(line); } catch { return null; } })
                .Where(x => x is not null).Cast<JournalEntry>().Reverse().Take(5000).ToList();
        }
    }

    internal void Clear() { lock (gate) { if (File.Exists(path)) File.Delete(path); } }
}
