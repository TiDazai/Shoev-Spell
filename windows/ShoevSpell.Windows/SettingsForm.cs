namespace ShoevSpell.Windows;

internal sealed class SettingsForm : Form
{
    private readonly CheckBox enabled = Option("Shoev Spell включён");
    private readonly CheckBox correction = Option("Исправлять опечатки автоматически");
    private readonly CheckBox punctuation = Option("Расставлять русскую пунктуацию");
    private readonly CheckBox capitalization = Option("Начинать предложения с заглавной буквы");
    private readonly CheckBox journal = Option("Сохранять локальный журнал исправлений");
    private readonly TextBox exclusions = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Consolas", 10) };

    internal SettingsForm(Icon icon)
    {
        Text = "Настройки Shoev Spell"; Icon = icon; StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(680, 560); Size = new Size(760, 620); BackColor = Color.White;
        var header = new Panel { Dock = DockStyle.Top, Height = 105, BackColor = Branding.Burgundy };
        var logo = new PictureBox { Image = Image.FromFile(Path.Combine(AppContext.BaseDirectory, "app-icon.png")), SizeMode = PictureBoxSizeMode.Zoom, Bounds = new Rectangle(18, 12, 78, 78) };
        var title = new Label { Text = "Shoev Spell", ForeColor = Branding.Platinum, Font = new Font("Segoe UI", 22, FontStyle.Bold), AutoSize = true, Location = new Point(112, 20) };
        var subtitle = new Label { Text = "Локальная проверка текста для Windows", ForeColor = Color.FromArgb(225, 210, 215), Font = new Font("Segoe UI", 10), AutoSize = true, Location = new Point(115, 62) };
        header.Controls.AddRange([logo, title, subtitle]);

        var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(14, 7) };
        tabs.TabPages.Add(BuildGeneral()); tabs.TabPages.Add(BuildSafety()); tabs.TabPages.Add(BuildAbout());
        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 62, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(12) };
        var save = new Button { Text = "Сохранить", Width = 120, Height = 34, BackColor = Branding.Burgundy, ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
        var cancel = new Button { Text = "Отмена", Width = 100, Height = 34 };
        save.Click += (_, _) => { Save(); DialogResult = DialogResult.OK; Close(); }; cancel.Click += (_, _) => Close();
        bottom.Controls.AddRange([save, cancel]); Controls.Add(tabs); Controls.Add(bottom); Controls.Add(header);
        LoadValues();
    }

    private TabPage BuildGeneral()
    {
        var page = Page("Поведение");
        var layout = Stack();
        layout.Controls.Add(Section("Основные функции"));
        layout.Controls.AddRange([enabled, correction, punctuation, capitalization, journal]);
        layout.Controls.Add(Help("Исправления выполняются при завершении слова. Интернет и облачные API не используются."));
        page.Controls.Add(layout); return page;
    }
    private TabPage BuildSafety()
    {
        var page = Page("Исключения"); var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(22), RowCount = 4, ColumnCount = 1 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(Section("Не обрабатывать в этих программах"));
        layout.Controls.Add(Help("Укажите имена процессов по одному в строке, например Code или devenv.")); layout.Controls.Add(exclusions);
        layout.Controls.Add(Help("Стандартные парольные поля, терминалы, IDE и менеджеры паролей пропускаются автоматически.")); page.Controls.Add(layout); return page;
    }
    private static TabPage BuildAbout()
    {
        var page = Page("О программе"); var layout = Stack(); layout.Controls.Add(Section("Shoev Spell для Windows"));
        layout.Controls.Add(Help("Полноценная Windows-версия Shoev Spell с тем же локальным русско-английским словарём, что и версия для macOS.\n\nВерсия 0.1.1 • данные хранятся только на этом компьютере.")); page.Controls.Add(layout); return page;
    }
    private void LoadValues()
    {
        enabled.Checked = SettingsStore.GetBool("Enabled", true); correction.Checked = SettingsStore.GetBool("Correction", true);
        punctuation.Checked = SettingsStore.GetBool("Punctuation", true); capitalization.Checked = SettingsStore.GetBool("Capitalization", true);
        journal.Checked = SettingsStore.GetBool("Journal", true); exclusions.Lines = SettingsStore.GetExclusions();
    }
    private void Save()
    {
        SettingsStore.SetBool("Enabled", enabled.Checked); SettingsStore.SetBool("Correction", correction.Checked);
        SettingsStore.SetBool("Punctuation", punctuation.Checked); SettingsStore.SetBool("Capitalization", capitalization.Checked);
        SettingsStore.SetBool("Journal", journal.Checked); SettingsStore.SetExclusions(exclusions.Lines);
    }
    private static CheckBox Option(string text) => new() { Text = text, AutoSize = true, Font = new Font("Segoe UI", 10), Margin = new Padding(4, 8, 4, 8) };
    private static Label Section(string text) => new() { Text = text, AutoSize = true, Font = new Font("Segoe UI Semibold", 13), ForeColor = Branding.BurgundyDark, Margin = new Padding(3, 10, 3, 12) };
    private static Label Help(string text) => new() { Text = text, AutoSize = true, MaximumSize = new Size(650, 0), Font = new Font("Segoe UI", 9), ForeColor = Color.DimGray, Margin = new Padding(4, 10, 4, 10) };
    private static FlowLayoutPanel Stack() => new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(22) };
    private static TabPage Page(string title) => new(title) { BackColor = Color.White, Padding = new Padding(8) };
}

internal sealed class JournalForm : Form
{
    internal JournalForm(Icon icon, JournalStore store)
    {
        Text = "Журнал исправлений Shoev Spell"; Icon = icon; StartPosition = FormStartPosition.CenterScreen; Size = new Size(850, 520); BackColor = Color.White;
        var grid = new DataGridView { Dock = DockStyle.Fill, ReadOnly = true, AutoGenerateColumns = true, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, BackgroundColor = Color.White, BorderStyle = BorderStyle.None };
        grid.DataSource = store.Read().Select(x => new { Время = x.Time.ToString("g"), Приложение = x.Application, Было = x.Original, Стало = x.Replacement }).ToList();
        var bar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 54, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(10) };
        var clear = new Button { Text = "Очистить журнал", Width = 140, Height = 32 };
        clear.Click += (_, _) => { if (MessageBox.Show("Удалить все записи?", "Shoev Spell", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes) { store.Clear(); grid.DataSource = null; } };
        bar.Controls.Add(clear); Controls.Add(grid); Controls.Add(bar);
    }
}
