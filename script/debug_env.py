"""Передаёт локальный .env через stdin при явном запуске под LLDB."""
import os


def __lldb_init_module(debugger, _dictionary):
    target = debugger.GetSelectedTarget()
    configuration = target.GetLaunchInfo()
    if not configuration.AddOpenFileAction(0, os.environ["BLOT_ENV_FILE"], True, False):
        raise RuntimeError("Не удалось открыть .env для отлаживаемого приложения")
    configuration.SetEnvironmentEntries(["BLOT_ENV_STDIN=1"], True)
    target.SetLaunchInfo(configuration)
