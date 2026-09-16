using System.Diagnostics;
using Microsoft.Win32;

namespace ShoevSpell.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Contains("--self-test")) return SelfTest.Run();
        using var singleInstance = new Mutex(true, "ShoevSpell.Windows.SingleInstance", out var created);
        if (!created) return 0;
        Application.Run(new SpellApplication(!args.Contains("--background")));
        return 0;
    }
}

internal static class SelfTest
{
    internal static int Run()
    {
        using var lexicon = new Lexicon();
        return lexicon.Score("привет", 1) is > 0
            && lexicon.Score("hello", 0) is > 0
            && CorrectionEngine.Find("превет", lexicon) == "привет" ? 0 : 1;
    }
}

internal sealed class SpellApplication : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly NotifyIcon tray;
    private readonly KeyboardHook hook;
    private readonly SpellEngine engine;
    private readonly ToolStripMenuItem enabledItem;
    private readonly ToolStripMenuItem correctionItem;
    private readonly ToolStripMenuItem punctuationItem;
    private readonly ToolStripMenuItem capitalizationItem;
    private readonly ToolStripMenuItem startupItem;
    private readonly Icon appIcon;
    private readonly JournalStore journal;

    public SpellApplication(bool showWindow)
    {
        appIcon = Branding.LoadIcon();
        journal = new JournalStore();
        var lexicon = new Lexicon();
        engine = new SpellEngine(lexicon);
        engine.Corrected += journal.Record;
        hook = new KeyboardHook(engine.HandleKey);

        enabledItem = CheckItem("Включено", "Enabled", true);
        correctionItem = CheckItem("Исправлять опечатки", "Correction", true);
        punctuationItem = CheckItem("Русская пунктуация", "Punctuation", true);
        capitalizationItem = CheckItem("Заглавные буквы", "Capitalization", true);
        startupItem = new ToolStripMenuItem("Запускать вместе с Windows") { Checked = IsStartupEnabled(), CheckOnClick = true };
        startupItem.CheckedChanged += (_, _) => SetStartup(startupItem.Checked);

        var menu = new ContextMenuStrip();
        menu.Items.AddRange([enabledItem, correctionItem, punctuationItem, capitalizationItem,
            new ToolStripSeparator(), startupItem, new ToolStripSeparator(),
            new ToolStripMenuItem("Настройки…", null, (_, _) => OpenSettings()),
            new ToolStripMenuItem("Журнал исправлений…", null, (_, _) => OpenJournal()),
            new ToolStripSeparator(),
            new ToolStripMenuItem("О Shoev Spell", null, (_, _) => MessageBox.Show(
                "Shoev Spell для Windows\n\nЛокальное исправление русских и английских опечаток.\nДанные не отправляются в интернет.",
                "Shoev Spell", MessageBoxButtons.OK, MessageBoxIcon.Information)),
            new ToolStripMenuItem("Выход", null, (_, _) => ExitThread())]);

        tray = new NotifyIcon
        {
            Text = "Shoev Spell",
            Icon = appIcon,
            Visible = true,
            ContextMenuStrip = menu
        };
        tray.DoubleClick += (_, _) => OpenSettings();
        hook.Start();
        if (showWindow)
        {
            var opener = new System.Windows.Forms.Timer { Interval = 250 };
            opener.Tick += (_, _) => { opener.Stop(); opener.Dispose(); OpenSettings(); };
            opener.Start();
        }
    }

    private void OpenSettings()
    {
        using var window = new SettingsForm(appIcon);
        window.ShowDialog();
        enabledItem.Checked = SettingsStore.GetBool("Enabled", true);
        correctionItem.Checked = SettingsStore.GetBool("Correction", true);
        punctuationItem.Checked = SettingsStore.GetBool("Punctuation", true);
        capitalizationItem.Checked = SettingsStore.GetBool("Capitalization", true);
    }

    private void OpenJournal()
    {
        using var window = new JournalForm(appIcon, journal);
        window.ShowDialog();
    }

    private ToolStripMenuItem CheckItem(string title, string key, bool defaultValue)
    {
        var value = SettingsStore.GetBool(key, defaultValue);
        var item = new ToolStripMenuItem(title) { Checked = value, CheckOnClick = true };
        item.CheckedChanged += (_, _) => SettingsStore.SetBool(key, item.Checked);
        return item;
    }

    protected override void ExitThreadCore()
    {
        hook.Dispose();
        tray.Visible = false;
        tray.Dispose();
        base.ExitThreadCore();
    }

    private static bool IsStartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue("Shoev Spell") is string;
    }

    private static void SetStartup(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue("Shoev Spell", $"\"{Environment.ProcessPath}\" --background");
        else key.DeleteValue("Shoev Spell", false);
    }
}

internal static class SettingsStore
{
    internal static readonly string DirectoryPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Shoev Spell");
    private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");
    private static Dictionary<string, bool>? values;
    private static string[]? exclusionsCache;

    internal static bool GetBool(string key, bool fallback)
    {
        EnsureLoaded();
        return values!.TryGetValue(key, out var value) ? value : fallback;
    }

    internal static void SetBool(string key, bool value)
    {
        EnsureLoaded();
        values![key] = value;
        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(FilePath, System.Text.Json.JsonSerializer.Serialize(values));
    }

    internal static string[] GetExclusions()
    {
        if (exclusionsCache is not null) return exclusionsCache;
        var path = Path.Combine(DirectoryPath, "exclusions.txt");
        try { exclusionsCache = File.ReadAllLines(path).Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(); }
        catch { exclusionsCache = []; }
        return exclusionsCache;
    }

    internal static void SetExclusions(IEnumerable<string> values)
    {
        Directory.CreateDirectory(DirectoryPath);
        exclusionsCache = values.Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        File.WriteAllLines(Path.Combine(DirectoryPath, "exclusions.txt"), exclusionsCache);
    }

    private static void EnsureLoaded()
    {
        if (values is not null) return;
        try { values = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, bool>>(File.ReadAllText(FilePath)); }
        catch { values = []; }
        values ??= [];
    }
}
