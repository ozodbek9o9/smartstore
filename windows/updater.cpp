#include <windows.h>
#include <shellapi.h>

#include <filesystem>
#include <string>
#include <vector>

namespace fs = std::filesystem;

std::wstring ArgumentValue(int argc, wchar_t** argv, const wchar_t* name) {
  for (int i = 1; i + 1 < argc; ++i) {
    if (std::wstring(argv[i]) == name) return argv[i + 1];
  }
  return L"";
}

std::wstring EscapePowerShellPath(const fs::path& path) {
  std::wstring value = path.wstring();
  std::wstring escaped;
  for (wchar_t character : value) {
    escaped += character;
    if (character == L'\'') escaped += L'\'';
  }
  return L"'" + escaped + L"'";
}

int RunPowerShell(const std::wstring& command) {
  std::wstring commandLine = L"powershell.exe -NoProfile -NonInteractive "
                             L"-ExecutionPolicy Bypass -Command \"" + command + L"\"";
  std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
  mutableCommand.push_back(L'\0');

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(nullptr, mutableCommand.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    return -1;
  }
  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exitCode = 1;
  GetExitCodeProcess(process.hProcess, &exitCode);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return static_cast<int>(exitCode);
}

bool WaitForParent(unsigned long parentPid) {
  HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, parentPid);
  if (parent == nullptr) return true;
  WaitForSingleObject(parent, INFINITE);
  CloseHandle(parent);
  return true;
}

bool CopyFileWithBackup(const fs::path& source, const fs::path& installDir,
                        const fs::path& stagingDir, const fs::path& backupDir,
                        std::vector<fs::path>* changedFiles) {
  const fs::path relative = fs::relative(source, stagingDir);
  const fs::path destination = installDir / relative;
  const fs::path backup = backupDir / relative;
  try {
    if (fs::exists(destination)) {
      fs::create_directories(backup.parent_path());
      fs::copy_file(destination, backup, fs::copy_options::overwrite_existing);
    }
    fs::create_directories(destination.parent_path());
    fs::copy_file(source, destination, fs::copy_options::overwrite_existing);
    changedFiles->push_back(relative);
    return true;
  } catch (...) {
    return false;
  }
}

void Rollback(const fs::path& installDir, const fs::path& backupDir,
              const std::vector<fs::path>& changedFiles) {
  for (const fs::path& relative : changedFiles) {
    const fs::path destination = installDir / relative;
    const fs::path backup = backupDir / relative;
    try {
      if (fs::exists(backup)) {
        fs::copy_file(backup, destination, fs::copy_options::overwrite_existing);
      } else if (fs::exists(destination)) {
        fs::remove(destination);
      }
    } catch (...) {
    }
  }
}

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, wchar_t*, int) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) return 2;

  const auto parentPid = std::stoul(ArgumentValue(argc, argv, L"--parent-pid"));
  const fs::path installDir = ArgumentValue(argc, argv, L"--install-dir");
  const fs::path package = ArgumentValue(argc, argv, L"--package");
  const std::wstring expectedHash = ArgumentValue(argc, argv, L"--sha256");
  const fs::path restartExe = ArgumentValue(argc, argv, L"--restart-exe");
  LocalFree(argv);

  if (installDir.empty() || package.empty() || restartExe.empty() ||
      expectedHash.size() != 64 || !fs::exists(package)) {
    return 2;
  }

  WaitForParent(parentPid);

  const fs::path root = fs::temp_directory_path() / L"smartstore-updater";
  const fs::path staging = root / L"staging";
  const fs::path backup = root / L"backup";
  fs::remove_all(root);
  fs::create_directories(staging);
  fs::create_directories(backup);

  const std::wstring hashCommand =
      L"$h=(Get-FileHash -Algorithm SHA256 -LiteralPath " +
      EscapePowerShellPath(package) + L").Hash.ToLower(); "
      L"if ($h -ne '" + expectedHash + L"') { exit 1 }";
  if (RunPowerShell(hashCommand) != 0) {
    fs::remove_all(root);
    return 3;
  }

  const std::wstring extractCommand =
      L"Expand-Archive -LiteralPath " + EscapePowerShellPath(package) +
      L" -DestinationPath " + EscapePowerShellPath(staging) + L" -Force";
  if (RunPowerShell(extractCommand) != 0) {
    fs::remove_all(root);
    return 4;
  }

  fs::path application = staging / L"app";
  if (!fs::exists(application)) application = staging;
  std::vector<fs::path> changedFiles;
  try {
    for (const auto& entry : fs::recursive_directory_iterator(application)) {
      if (!entry.is_regular_file()) continue;
      if (entry.path().filename() == L"updater.exe") continue;
      if (!CopyFileWithBackup(entry.path(), installDir, application, backup,
                              &changedFiles)) {
        Rollback(installDir, backup, changedFiles);
        fs::remove_all(root);
        return 5;
      }
    }
  } catch (...) {
    Rollback(installDir, backup, changedFiles);
    fs::remove_all(root);
    return 6;
  }

  if (!fs::exists(restartExe)) {
    Rollback(installDir, backup, changedFiles);
    fs::remove_all(root);
    return 7;
  }

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  std::wstring commandLine = L"\"" + restartExe.wstring() + L"\"";
  std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
  mutableCommand.push_back(L'\0');
  const BOOL started = CreateProcessW(nullptr, mutableCommand.data(), nullptr,
                                      nullptr, FALSE, 0, nullptr,
                                      installDir.wstring().c_str(), &startup,
                                      &process);
  if (!started) {
    Rollback(installDir, backup, changedFiles);
    fs::remove_all(root);
    return 8;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  fs::remove_all(root);
  return 0;
}
