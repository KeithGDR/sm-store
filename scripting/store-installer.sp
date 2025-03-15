#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 524288

#include <sourcemod>
#include <colorlib>
#include <store>
#include <json>

Handle g_DBCache[MAXPLAYERS + 1];
bool g_ClearTables[MAXPLAYERS + 1];
bool g_ImportItems[MAXPLAYERS + 1];

bool g_Installing[MAXPLAYERS + 1];
bool g_ItemsOnly[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name        = "[Store] Installer",
	author      = "Alongub, KeithGDR",
	description = "Installer component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	RegConsoleCmd("sm_install", Command_Install, "Starts the installation process for the Store system.");
	RegConsoleCmd("sm_installitems", Command_InstallItems, "Install the item configs specifically.");
	RegConsoleCmd("sm_installitemsconfig", Command_InstallItemsConfig, "Installs a specific item config.");
}

public Action Command_Install(int client, int args) {
	if (!CheckCommandAccess(client, "store_install", ADMFLAG_ROOT)) {
		ReplyToCommand(client, "%sYou do not have the correct privileges.", STORE_PREFIX_CONSOLE);
		return Plugin_Handled;
	}

	if (g_ItemsOnly[client] || g_Installing[client]) {
		return Plugin_Handled;
	}

	g_Installing[client] = true;
	StartInstallation(client);

	return Plugin_Handled;
}

public Action Command_InstallItems(int client, int args) {
	if (!CheckCommandAccess(client, "store_install", ADMFLAG_ROOT)) {
		ReplyToCommand(client, "%sYou do not have the correct privileges.", STORE_PREFIX_CONSOLE);
		return Plugin_Handled;
	}

	if (g_Installing[client] || g_ItemsOnly[client]) {
		return Plugin_Handled;
	}

	Handle db = Store_GetDatabase();

	if (db == null) {
		Store_PrintToChat(client, "The database is currently disconnected, cancelling item installs...");
		return Plugin_Handled;
	}

	g_DBCache[client] = db;
	g_ItemsOnly[client] = true;

	AskConfirmItemsData(client);
	return Plugin_Handled;
}

public Action Command_InstallItemsConfig(int client, int args) {
	if (!CheckCommandAccess(client, "store_install", ADMFLAG_ROOT)) {
		ReplyToCommand(client, "%sYou do not have the correct privileges.", STORE_PREFIX_CONSOLE);
		return Plugin_Handled;
	}

	if (g_Installing[client] || g_ItemsOnly[client]) {
		return Plugin_Handled;
	}

	if (args == 0) {
		char command[32];
		GetCmdArg(0, command, sizeof(command));
		Store_PrintToChat(client, "Usage: %s <config-name>", command);
		return Plugin_Handled;
	}

	char name[64];
	GetCmdArg(1, name, sizeof(name));

	if (StrContains(name, ".json", false) != -1) {
		ReplaceString(name, sizeof(name), ".json", "", false);
	}

	Handle db = Store_GetDatabase();

	if (db == null) {
		Store_PrintToChat(client, "The database is currently disconnected, cancelling item config install...");
		return Plugin_Handled;
	}

	g_DBCache[client] = db;
	g_ItemsOnly[client] = true;

	char config[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, config, sizeof(config), "configs/store/json-import/%s.json", name);

	if (!FileExists(config)) {
		Store_PrintToChat(client, "Error while parsing item config: Missing File: %s", config);
		EndInstallation(client);
		return Plugin_Handled;
	}

	ImportItemsConfig(config, db, client);
	return Plugin_Handled;
}

void StartInstallation(int client = 0) {
	Store_PrintToChat(client, "Starting installation process...");

	Handle db = Store_GetDatabase();

	if (db == null) {
		Store_PrintToChat(client, "The database is currently disconnected, cancelling installation...");
		EndInstallation(client);
		return;
	}

	g_DBCache[client] = db;

	char query[512];
	FormatEx(query, sizeof(query), "SHOW TABLES LIKE 'store_categories';");
	SQL_TQuery(db, OnCheckExistingInstall, query, client);
}

public void OnCheckExistingInstall(Handle db, Handle results, const char[] error, any data) {
	int client = data;
	
	if (SQL_HasResultSet(results) && SQL_GetRowCount(results) > 0) {
		Store_PrintToChat(client, "Tables found, would you like to clear them? - (yes, no)");
		g_ClearTables[client] = true;
	} else {
		CreateTables(db, client);
	}
}

void CreateTables(Handle db, int client = 0) {
	Store_PrintToChat(client, "Creating tables...");

	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "configs/store/sql-init-scripts/store.sql");

	if (!FileExists(filePath))
	{
		Store_PrintToChat(client, "Error while creating tables: Can't find file: %s", filePath);
		EndInstallation(client);
		return;
	}

	File file = OpenFile(filePath, "r");

	if (file == null)
	{
		Store_PrintToChat(client, "Error while creating tables: Can't open file: %s", filePath);
		EndInstallation(client);
		return;
	}

	char query[4096];
	char line[1024];

	while (ReadFileLine(file, line, sizeof(line)))
	{
		TrimString(line);

		if (strlen(line) == 0)
			continue;

		StrCat(query, sizeof(query), line);

		if (StrContains(line, ";") != -1)
		{
			SQL_TQuery(db, OnCreateTable, query, client);
			query[0] = '\0';
		}
	}

	CloseHandle(file);

	Store_PrintToChat(client, "Tables have been created.");
	AskConfirmItemsData(client);
}

public void OnCreateTable(Handle db, Handle results, const char[] error, any data) {
	
}

void AskConfirmItemsData(int client = 0) {
	Store_PrintToChat(client, "Import the items now? - (yes, no)");
	g_ImportItems[client] = true;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
	char answer[32];
	strcopy(answer, sizeof(answer), sArgs);
	TrimString(answer);

	if (g_ClearTables[client]) {
		g_ClearTables[client] = false;

		if (StrEqual(answer, "yes", false)) {
			ClearTables(g_DBCache[client], client);
		} else {
			AskConfirmItemsData(client);
		}
	} else if (g_ImportItems[client]) {
		g_ImportItems[client] = false;

		if (StrEqual(answer, "yes", false)) {
			ImportItemsData(g_DBCache[client], client);
		} else {
			if (!g_ItemsOnly[client]) {
				EndInstallation(client, true);
			}
		}
	}
}

void ClearTables(Handle db, int client = 0) {
	Store_PrintToChat(client, "Clearing tables...");

	Transaction trans = SQL_CreateTransaction();
	char query[512];

	FormatEx(query, sizeof(query), "TRUNCATE TABLE store_categories;");
	trans.AddQuery(query);

	FormatEx(query, sizeof(query), "TRUNCATE TABLE store_items;");
	trans.AddQuery(query);

	FormatEx(query, sizeof(query), "TRUNCATE TABLE store_users;");
	trans.AddQuery(query);

	FormatEx(query, sizeof(query), "TRUNCATE TABLE store_users_items;");
	trans.AddQuery(query);

	FormatEx(query, sizeof(query), "TRUNCATE TABLE store_users_items_loadouts;");
	trans.AddQuery(query);

	SQL_ExecuteTransaction(db, trans, OnSuccess, OnFailure, client);
}

public void OnSuccess(Database db, any data, int numQueries, Handle[] results, any[] queryData) {
	int client = data;
	Store_PrintToChat(client, "Tables have been cleared successfully.");
	AskConfirmItemsData(client);
}

public void OnFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	int client = data;
	Store_PrintToChat(client, "Error while clearing table %i/%i: %s", failIndex, numQueries, error);
	EndInstallation(client);
}

void ImportItemsData(Handle db, int client = 0) {
	char file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), "configs/store/json-import/");

	DirectoryListing dir = OpenDirectory(file);

	if (dir == null)
	{
		Store_PrintToChat(client, "Error while importing items data: Can't find folder: %s", file);
		if (!g_ItemsOnly[client]) {
			EndInstallation(client);
		}
		return;
	}

	char fileName[PLATFORM_MAX_PATH];
	FileType fileType;

	while (ReadDirEntry(dir, fileName, sizeof(fileName), fileType))
	{
		if (fileType == FileType_File && StrContains(fileName, ".json", false) != -1)
		{
			Format(fileName, sizeof(fileName), "%s/%s", file, fileName);
			ImportItemsConfig(fileName, db, client);
		}
	}

	CloseHandle(dir);

	if (!g_ItemsOnly[client]) {
		EndInstallation(client, true);
	} else {
		EndItemInstalls(client, true);
	}
}

void ImportItemsConfig(const char[] config, Handle db, int client = 0) {
	File file = OpenFile(config, "r");

	if (!FileExists(config)) {
		Store_PrintToChat(client, "Error while importing items config: Can't open file: %s", config);
		return;
	}

	if (file == null) {
		Store_PrintToChat(client, "Error while importing items config: Can't open file: %s", config);
		return;
	}

	CloseHandle(file);

	JSON_Object obj = json_read_from_file(config);

	if (obj == null) {
		Store_PrintToChat(client, "Error while importing items config: Corrupted JSON: %s", config);
		return;
	}

	char query[1024];
	Transaction trans = SQL_CreateTransaction();

	JSON_Array categories = view_as<JSON_Array>(obj.GetObject("categories"));

	for (int i = 0; i < categories.Length; i++) {
		JSON_Object category = categories.GetObject(i);

		char display_name[64];
		category.GetString("display_name", display_name, sizeof(display_name));

		char description[64];
		category.GetString("description", description, sizeof(description));

		char require_plugin[64];
		category.GetString("require_plugin", require_plugin, sizeof(require_plugin));

		FormatEx(query, sizeof(query), "INSERT INTO `store_categories` (display_name, description, require_plugin) VALUES ('%s', '%s', '%s');", display_name, description, require_plugin);

		JSON_Array items = view_as<JSON_Array>(category.GetObject("items"));
		trans.AddQuery(query, items.DeepCopy());
	}

	SQL_ExecuteTransaction(db, trans, OnSuccess2, OnFailure2, categories);
}

public void OnSuccess2(Database db, any data, int numQueries, Handle[] results, any[] queryData) {
	JSON_Object categories = view_as<JSON_Object>(data);	
	categories.Cleanup();

	char query[4096];
	Transaction trans = SQL_CreateTransaction();

	for (int i = 0; i < numQueries; i++) {
		int category_id = SQL_GetInsertId(results[i]);
		JSON_Array items = view_as<JSON_Array>(queryData[i]);

		for (int x = 0; x < items.Length; x++) {
			JSON_Object item = items.GetObject(x);

			char name[64];
			item.GetString("name", name, sizeof(name));

			char display_name[64];
			item.GetString("display_name", display_name, sizeof(display_name));

			char description[64];
			item.GetString("description", description, sizeof(description));

			char type[64];
			item.GetString("type", type, sizeof(type));

			char loadout_slot[64];
			item.GetString("loadout_slot", loadout_slot, sizeof(loadout_slot));
			
			char price[16];
			item.GetString("price", price, sizeof(price));
			//int price = item.GetInt("price");

			JSON_Object attrs = item.GetObject("attrs");

			int size = json_encode_size(attrs);
			char[] buffer = new char[size];
			json_encode(attrs, buffer, size);

			char is_buyable[16];
			item.GetString("is_buyable", is_buyable, sizeof(is_buyable));
			//bool is_buyable = item.GetBool("is_buyable");

			char is_tradeable[16];
			item.GetString("is_tradeable", is_tradeable, sizeof(is_tradeable));
			//bool is_tradeable = item.GetBool("is_tradeable");

			char is_refundable[16];
			item.GetString("is_refundable", is_refundable, sizeof(is_refundable));
			//bool is_refundable = item.GetBool("is_refundable");

			//char expiry_time[16];
			//item.GetString("expiry_time", expiry_time, sizeof(expiry_time));
			int expiry_time = item.GetInt("expiry_time");

			char flags[64];
			item.GetString("flags", flags, sizeof(flags));

			FormatEx(query, sizeof(query), "INSERT INTO `store_items` (name, display_name, description, type, loadout_slot, price, category_id, attrs, is_buyable, is_tradeable, is_refundable, expiry_time, flags) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%i', '%s', '%s', '%s', '%s', '%i', '%s');", name, display_name, description, type, loadout_slot, price, category_id, buffer, is_buyable, is_tradeable, is_refundable, expiry_time, flags);
			trans.AddQuery(query);
		}

		items.Cleanup();
	}

	SQL_ExecuteTransaction(db, trans, OnSuccess3, OnFailure3);
}

public void OnFailure2(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	JSON_Object categories = view_as<JSON_Object>(data);	
	categories.Cleanup();
}

public void OnSuccess3(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{

}

public void OnFailure3(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	int client = data;
	Store_PrintToChat(client, "Error while installing items %i/%i: %s", failIndex, numQueries, error);
	EndInstallation(client);
}

void EndInstallation(int client = 0, bool success = false) {
	Store_PrintToChat(client, "Install has been completed %s.", success ? "successfully" : "unsuccessfully");

	if (success) {
		Store_PrintToChat(client, "Please restart your server.");
	}
	
	if (g_DBCache[client] != null) {
		CloseHandle(g_DBCache[client]);
	}

	g_DBCache[client] = null;
	g_ClearTables[client] = false;
	g_ImportItems[client] = false;

	g_Installing[client] = false;
	g_ItemsOnly[client] = false;
}

void EndItemInstalls(int client = 0, bool success = false) {
	Store_PrintToChat(client, "Item config installs has been completed %s.", success ? "successfully" : "unsuccessfully");

	if (success) {
		Store_PrintToChat(client, "Please restart your server.");
	}
	
	if (g_DBCache[client] != null) {
		CloseHandle(g_DBCache[client]);
	}

	g_DBCache[client] = null;
	g_ClearTables[client] = false;
	g_ImportItems[client] = false;

	g_Installing[client] = false;
	g_ItemsOnly[client] = false;
}

public void OnClientDisconnect(int client) {
	if (g_DBCache[client] != null) {
		CloseHandle(g_DBCache[client]);
	}

	g_DBCache[client] = null;
	g_ClearTables[client] = false;
	g_ImportItems[client] = false;

	g_Installing[client] = false;
	g_ItemsOnly[client] = false;
}