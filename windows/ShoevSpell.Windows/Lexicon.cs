using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace ShoevSpell.Windows;

internal sealed class Lexicon : IDisposable
{
    private const string ExpectedHash = "493B2B9E1AC83D755A77B24D031AFFB6A0BA05AC5CFEEA0C9AFF16AD054A4025";
    private nint database;
    private nint statement;
    internal Lexicon()
    {
        try
        {
            var path = Prepare();
            if (Sqlite.sqlite3_open_v2(Utf8(path), out database, 1, 0) != 0) return;
            Sqlite.sqlite3_prepare_v2(database, Utf8("SELECT score FROM words WHERE language=?1 AND word=?2"), -1, out statement, 0);
        }
        catch { database = statement = 0; }
    }

    internal int? Score(string word, int language)
    {
        if (statement == 0) return null;
        lock (this)
        {
            Sqlite.sqlite3_reset(statement); Sqlite.sqlite3_clear_bindings(statement);
            Sqlite.sqlite3_bind_int(statement, 1, language);
            var value = Utf8(word); Sqlite.sqlite3_bind_text(statement, 2, value, value.Length - 1, new nint(-1));
            return Sqlite.sqlite3_step(statement) == 100 ? Sqlite.sqlite3_column_int(statement, 0) : null;
        }
    }

    private static string Prepare()
    {
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Shoev Spell");
        var databasePath = Path.Combine(directory, "lexicon.sqlite3");
        if (File.Exists(databasePath)) return databasePath;
        Directory.CreateDirectory(directory);
        var parts = Directory.GetFiles(Path.Combine(AppContext.BaseDirectory, "lexicon-parts"), "lexicon.sqlite3.gz.part-*").Order().ToArray();
        if (parts.Length == 0) throw new FileNotFoundException("Не найдены части словаря");
        var archivePath = Path.Combine(directory, "lexicon.sqlite3.gz.tmp");
        using (var output = File.Create(archivePath)) foreach (var part in parts) using (var input = File.OpenRead(part)) input.CopyTo(output);
        using (var stream = File.OpenRead(archivePath)) if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(ExpectedHash, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Повреждён архив словаря");
        var temporary = databasePath + ".tmp";
        using (var source = new GZipStream(File.OpenRead(archivePath), CompressionMode.Decompress)) using (var target = File.Create(temporary)) source.CopyTo(target);
        File.Move(temporary, databasePath, true); File.Delete(archivePath); return databasePath;
    }

    private static byte[] Utf8(string value) => Encoding.UTF8.GetBytes(value + '\0');
    public void Dispose() { if (statement != 0) Sqlite.sqlite3_finalize(statement); if (database != 0) Sqlite.sqlite3_close(database); }

    private static class Sqlite
    {
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_open_v2(byte[] name, out nint db, int flags, nint vfs);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_prepare_v2(nint db, byte[] sql, int length, out nint statement, nint tail);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_bind_int(nint statement, int index, int value);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_bind_text(nint statement, int index, byte[] value, int length, nint destructor);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_step(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_column_int(nint statement, int column);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_reset(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_clear_bindings(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_finalize(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_close(nint db);
    }
}
