namespace Prism.Core.Logging;

public enum AppLogCategory
{
    App,
    Orchestrator,
    Engine,
    Hotkey,
    Permissions,
    TextIo,
    DeepL,
    Google,
    Azure,
    OpenAI,
    CustomHttp,
}

public interface IAppLog
{
    void Info(AppLogCategory category, string message);
    void Warning(AppLogCategory category, string message);
    void Error(AppLogCategory category, string message);
    void Debug(AppLogCategory category, string message);
}

public sealed class ConsoleAppLog : IAppLog
{
    public void Info(AppLogCategory category, string message) =>
        Write("INFO", category, message);

    public void Warning(AppLogCategory category, string message) =>
        Write("WARN", category, message);

    public void Error(AppLogCategory category, string message) =>
        Write("ERROR", category, message);

    public void Debug(AppLogCategory category, string message) =>
        Write("DEBUG", category, message);

    private static void Write(string level, AppLogCategory category, string message) =>
        System.Diagnostics.Debug.WriteLine($"[{level}][{category}] {message}");
}

public sealed class FileAppLog : IAppLog
{
    private readonly string _directory;
    private readonly object _lock = new();

    public FileAppLog(string? directory = null)
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _directory = directory ?? Path.Combine(root, "Prism", "logs");
        Directory.CreateDirectory(_directory);
    }

    public void Info(AppLogCategory category, string message) => Write("INFO", category, message);
    public void Warning(AppLogCategory category, string message) => Write("WARN", category, message);
    public void Error(AppLogCategory category, string message) => Write("ERROR", category, message);
    public void Debug(AppLogCategory category, string message) => Write("DEBUG", category, message);

    private void Write(string level, AppLogCategory category, string message)
    {
        var line = $"{DateTime.UtcNow:O} [{level}][{category}] {message}{Environment.NewLine}";
        var path = Path.Combine(_directory, $"prism-{DateTime.UtcNow:yyyyMMdd}.log");
        lock (_lock)
        {
            File.AppendAllText(path, line);
        }
    }
}
