using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly: AssemblyTitle("Installation de BASTOS")]
[assembly: AssemblyCompany("BASTOS")]
[assembly: AssemblyProduct("BASTOS")]
[assembly: AssemblyFileVersion("7.120.137.0")]
[assembly: AssemblyVersion("7.120.137.0")]
internal static class Setup {
    private const string Version = "7.120.137";
    private const string PayloadHash = "__PAYLOAD_HASH__";
    private const string ScriptHash = "__SCRIPT_HASH__";
    private static string Hash(string path) {
        using (var sha = SHA256.Create()) using (var stream = File.OpenRead(path))
            return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
    }
    private static void Plain(string path) {
        for (var dir = new DirectoryInfo(path); dir != null; dir = dir.Parent)
            if (dir.Exists && (dir.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Un lien ou une jonction redirige le dossier d'installation.");
    }
    private static void Extract(string name, string path, string expected) {
        using (var input = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if (input == null) throw new IOException("Ressource d'installation absente.");
            using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None)) input.CopyTo(output);
        }
        if (Hash(path) != expected) throw new IOException("Fichier d'installation endommagé.");
    }
    private static int Run(string testRoot, bool verify, out string output) {
        string parent = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BASTOS", "Setup");
        Plain(parent);
        Directory.CreateDirectory(parent);
        string temp = Path.Combine(parent, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        try {
            var script = Path.Combine(temp, "Installer.ps1");
            Extract("Installer.ps1", script, ScriptHash);
            Extract("Payload.zip", Path.Combine(temp, "BASTOS-" + Version + "-Payload.zip"), PayloadHash);
            string arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\"";
            if (verify) arguments += " -VerifyOnly";
            if (testRoot != null) {
                testRoot = Path.GetFullPath(testRoot);
                if (testRoot.IndexOf('"') >= 0) throw new ArgumentException("Destination invalide.");
                arguments += " -TestRoot \"" + testRoot.TrimEnd('\\') + "\"";
            }
            var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"), arguments);
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            start.StandardOutputEncoding = System.Text.Encoding.UTF8; start.StandardErrorEncoding = System.Text.Encoding.UTF8;
            using (var process = Process.Start(start)) {
                var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(600000)) { process.Kill(); throw new IOException("Délai d'installation dépassé. Consultez l'état de l'installation avant de réessayer."); }
                Task.WaitAll(stdout, stderr); output = stdout.Result + stderr.Result;
                return process.ExitCode;
            }
        } finally {
            Plain(temp);
            if (Directory.Exists(temp)) Directory.Delete(temp, true);
        }
    }
    [STAThread] private static int Main(string[] args) {
        string testRoot = null; bool verify = false, cli = args.Length > 0;
        try {
            for (int i = 0; i < args.Length; i++) {
                if (args[i] == "--verify-only") verify = true;
                else if (args[i] == "--test-root" && i + 1 < args.Length) testRoot = args[++i];
                else throw new ArgumentException("Argument inconnu.");
            }
            if (cli) {
                if (testRoot == null) throw new ArgumentException("Les contrôles automatisés exigent --test-root.");
                string text; int code = Run(testRoot, verify, out text);
                Directory.CreateDirectory(testRoot); File.WriteAllText(Path.Combine(testRoot, "Setup-result.txt"), text);
                return code;
            }
            if (!Environment.Is64BitOperatingSystem || Environment.OSVersion.Version.Build < 22000)
                throw new NotSupportedException("BASTOS nécessite Windows 11 x64.");
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            var window = new Form { Text = "Installation de BASTOS " + Version, ClientSize = new Size(590, 350), FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, StartPosition = FormStartPosition.CenterScreen };
            window.Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
            var heading = new Label { Text = "Bienvenue dans BASTOS", Font = new Font("Segoe UI", 17), AutoSize = true, Location = new Point(25, 22) };
            var explanation = new Label { Text = "Installe BASTOS pour votre compte Windows et crée un seul raccourci sur le Bureau.\r\n\r\nAucun réglage Windows, logiciel tiers ou opération de réinstallation n'est lancé par cette installation. Les droits administrateur sont demandés à l'ouverture de BASTOS.", AutoSize = false, Size = new Size(535, 115), Location = new Point(27, 72) };
            var status = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Size = new Size(535, 83), Location = new Point(27, 190), Text = "Destination : %LOCALAPPDATA%\\Programs\\BASTOS\r\nUne installation existante est conservée en sauvegarde." };
            var install = new Button { Text = "Installer BASTOS", Size = new Size(150, 36), Location = new Point(412, 293) };
            var close = new Button { Text = "Fermer", Size = new Size(90, 36), Location = new Point(312, 293) };
            var license = new Button { Text = "Licence", Size = new Size(90, 36), Location = new Point(27, 293) };
            bool busy = false;
            license.Click += delegate {
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("LICENSE.txt")) using (var reader = new StreamReader(stream)) {
                    var dialog = new Form { Text = "BASTOS — GPL-3.0-or-later", Size = new Size(760, 580), StartPosition = FormStartPosition.CenterParent };
                    dialog.Controls.Add(new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, WordWrap = true, Dock = DockStyle.Fill, Text = reader.ReadToEnd().Replace("\r\n", "\n").Replace("\n", "\r\n") }); dialog.ShowDialog(window);
                }
            };
            close.Click += delegate { window.Close(); };
            window.FormClosing += delegate(object sender, FormClosingEventArgs e) { if (busy) e.Cancel = true; };
            install.Click += async delegate {
                busy = true; install.Enabled = false; close.Enabled = false; status.Text = "Vérification et installation en cours…";
                try {
                    var result = await Task.Run(delegate { string text; int code = Run(null, false, out text); return Tuple.Create(code, text); });
                    status.Text = result.Item1 == 0 ? "BASTOS est installé. Vous pouvez fermer cette fenêtre et utiliser le raccourci BASTOS sur le Bureau." : "Installation non terminée.\r\n" + result.Item2;
                    install.Text = result.Item1 == 0 ? "Installé" : "Réessayer"; install.Enabled = result.Item1 != 0;
                } catch (Exception ex) { status.Text = "Installation non terminée : " + ex.Message; install.Enabled = true; }
                finally { busy = false; close.Enabled = true; }
            };
            window.Controls.AddRange(new Control[] { heading, explanation, status, license, close, install });
            Application.Run(window); return 0;
        } catch (Exception ex) {
            if (cli && testRoot != null && Directory.Exists(testRoot)) File.WriteAllText(Path.Combine(testRoot, "Setup-error.txt"), ex.Message);
            else if (!cli) MessageBox.Show(ex.Message, "Installation de BASTOS", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
