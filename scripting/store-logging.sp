#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colorlib>
#include <store>

#define PLUGIN_NAME_RESERVED_LENGTH 33

Handle g_log_file = null;
char g_log_level_names[][] = { "     ", "ERROR", "WARN ", "INFO ", "DEBUG", "TRACE" };
Store_LogLevel g_log_level = Store_LogLevelNone;
Store_LogLevel g_log_flush_level = Store_LogLevelNone;
bool g_log_errors_to_SM = false;
char g_current_date[20];

public Plugin myinfo =
{
	name        = "[Store] Logging",
	author      = "Alongub, KeithGDR",
	description = "Logging component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Store_GetLogLevel", Store_GetLogLevel_);
	CreateNative("Store_Log",         Store_Log_);
	CreateNative("Store_LogError",    Store_LogError_);
	CreateNative("Store_LogWarning",  Store_LogWarning_);
	CreateNative("Store_LogInfo",     Store_LogInfo_);
	CreateNative("Store_LogDebug",    Store_LogDebug_);
	CreateNative("Store_LogTrace",    Store_LogTrace_);
    
	RegPluginLibrary("store-logging");
    
	return APLRes_Success;
}

public void OnPluginStart() 
{
	LoadConfig();
	FormatTime(g_current_date, sizeof(g_current_date), "%Y-%m-%d", GetTime());
	CreateTimer(1.0, OnCheckDate, _, TIMER_REPEAT);
	if (g_log_level > Store_LogLevelNone)
		CreateLogFileOrTurnOffLogging();
}

void LoadConfig() 
{
	Handle kv = CreateKeyValues("root");
    
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/logging.cfg");
    
	if (!FileToKeyValues(kv, path))
    {
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	g_log_level = view_as<Store_LogLevel>(KvGetNum(kv, "log_level", 2));
	g_log_flush_level = view_as<Store_LogLevel>(KvGetNum(kv, "log_flush_level", 2));
	g_log_errors_to_SM = (KvGetNum(kv, "log_errors_to_SM", 1) > 0);

	CloseHandle(kv);
}

public void OnPluginEnd() 
{
	if (g_log_file != null)
		CloseLogFile();
}

public Action OnCheckDate(Handle timer)
{
	char new_date[20];
	FormatTime(new_date, sizeof(new_date), "%Y-%m-%d", GetTime());
    
	if (g_log_level > Store_LogLevelNone && !StrEqual(new_date, g_current_date)) 
    {
		strcopy(g_current_date, sizeof(g_current_date), new_date);
        
		if (g_log_file != null) 
        {
			WriteMessageToLog(null, Store_LogLevelInfo, "Date changed; switching log file", true);
			CloseLogFile();
		}
        
		CreateLogFileOrTurnOffLogging();
	}

	return Plugin_Continue;
}

void CloseLogFile() 
{
	WriteMessageToLog(null, Store_LogLevelInfo, "Logging stopped");
	FlushFile(g_log_file);
	CloseHandle(g_log_file);
	g_log_file = null;
}

bool CreateLogFileOrTurnOffLogging()
{
	char filename[128];
	int pos = BuildPath(Path_SM, filename, sizeof(filename), "logs/");
	FormatTime(filename[pos], sizeof(filename)-pos, "store_%Y-%m-%d.log", GetTime());
    
	if ((g_log_file = OpenFile(filename, "a")) == null) 
    {
		g_log_level = Store_LogLevelNone;
		LogError("Can't create store log file");
		return false;
	}
	else 
    {
		WriteMessageToLog(null, Store_LogLevelInfo, "Logging started", true);
		return true;
	}
}

public int Store_GetLogLevel_(Handle plugin, int num_params) 
{
	return view_as<int>(g_log_level);
}

public void Store_Log_(Handle plugin, int num_params) 
{
	Store_LogLevel log_level = view_as<Store_LogLevel>(GetNativeCell(1));
	if (g_log_level >= log_level) 
    {
		char message[10000], written;
		FormatNativeString(0, 2, 3, sizeof(message), written, message);
        
		if (g_log_file != null)
			WriteMessageToLog(plugin, log_level, message);
            
		if (log_level == Store_LogLevelError && g_log_errors_to_SM) 
        {
			ReplaceString(message, sizeof(message), "%", "%%");
			LogError(message);
		}
	}
}

public void Store_LogError_(Handle plugin, int num_params) 
{
	if (g_log_level >= Store_LogLevelError) 
    {
		char message[10000], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
        
		if (g_log_file != null)
        {
			WriteMessageToLog(plugin, Store_LogLevelError, message);
        }
         
		if (g_log_errors_to_SM) 
        {
			ReplaceString(message, sizeof(message), "%", "%%");
			LogError(message);
		}
	}
}

public void Store_LogWarning_(Handle plugin, int num_params) 
{
	if (g_log_level >= Store_LogLevelWarning && g_log_file != null) 
    {
		char message[10000], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessageToLog(plugin, Store_LogLevelWarning, message);
	}
}

public void Store_LogInfo_(Handle plugin, int num_params) 
{
	if (g_log_level >= Store_LogLevelInfo && g_log_file != null) 
    {
		char message[10000], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessageToLog(plugin, Store_LogLevelInfo, message);
	}
}

public void Store_LogDebug_(Handle plugin, int num_params) 
{
	if (g_log_level >= Store_LogLevelDebug && g_log_file != null) 
    {
		char message[10000], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessageToLog(plugin, Store_LogLevelDebug, message);
	}
}

public void Store_LogTrace_(Handle plugin, int num_params) 
{
	if (g_log_level >= Store_LogLevelTrace && g_log_file != null) 
    {
		char message[10000], written;
		FormatNativeString(0, 1, 2, sizeof(message), written, message);
		WriteMessageToLog(plugin, Store_LogLevelTrace, message);
	}
}

void WriteMessageToLog(Handle plugin, Store_LogLevel log_level, const char[] message, bool force_flush = false) 
{
	char log_line[10000];
	PrepareLogLine(plugin, log_level, message, log_line, sizeof(log_line));
	WriteFileString(g_log_file, log_line, false);
    
	if (log_level <= g_log_flush_level || force_flush)
		FlushFile(g_log_file);
}

void PrepareLogLine(Handle plugin, Store_LogLevel log_level, const char[] message, char[] log_line, int size) 
{
	char plugin_name[100];
	GetPluginFilename(plugin, plugin_name, sizeof(plugin_name)-1);
	// Make windows consistent with unix
	ReplaceString(plugin_name, sizeof(plugin_name), "\\", "/");
	int name_end = size;
	plugin_name[name_end++] = ']';
	for (int end=PLUGIN_NAME_RESERVED_LENGTH-1; name_end<end; ++name_end)
		plugin_name[name_end] = ' ';
	plugin_name[name_end++] = 0;
	FormatTime(log_line, size, "%Y-%m-%d %H:%M:%S [", GetTime());
	int pos = strlen(log_line);
	pos += strcopy(log_line[pos], size-pos, plugin_name);
	log_line[pos++] = ' ';
	pos += strcopy(log_line[pos], size-pos-5, g_log_level_names[log_level]);
	log_line[pos++] = ' ';
	log_line[pos++] = '|';
	log_line[pos++] = ' ';
	pos += strcopy(log_line[pos], size-pos-2, message);
	log_line[pos++] = '\n';
	log_line[pos++] = 0;
}