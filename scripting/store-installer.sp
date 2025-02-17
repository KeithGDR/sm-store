#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
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
		PrintToChat(client, "%sThe database is currently disconnected, cancelling item installs...", STORE_PREFIX_CONSOLE);
		EndInstallation(client);
		return Plugin_Handled;
	}

	g_DBCache[client] = db;
	g_ItemsOnly[client] = true;

	AskConfirmItemsData(client);
	return Plugin_Handled;
}

void StartInstallation(int client = 0) {
	PrintToChat(client, "%sStarting installation process...", STORE_PREFIX_CONSOLE);

	Handle db = Store_GetDatabase();

	if (db == null) {
		PrintToChat(client, "%sThe database is currently disconnected, cancelling installation...", STORE_PREFIX_CONSOLE);
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
	
	if (SQL_HasResultSet(results)) {
		PrintToChat(client, "%sTables found, would you like to clear them? - (yes, no)", STORE_PREFIX_CONSOLE);
		g_ClearTables[client] = true;
	} else {
		CreateTables(db, client);
	}
}

void CreateTables(Handle db, int client = 0) {
	PrintToChat(client, "%sCreating tables...", STORE_PREFIX_CONSOLE);

	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "configs/store/sql-init-scripts/store.sql");

	if (!FileExists(filePath))
	{
		PrintToChat(client, "%sError while creating tables: Can't find file: %s", STORE_PREFIX_CONSOLE, filePath);
		EndInstallation(client);
		return;
	}

	File file = OpenFile(filePath, "r");

	if (file == null)
	{
		PrintToChat(client, "%sError while creating tables: Can't open file: %s", STORE_PREFIX_CONSOLE, filePath);
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

	PrintToChat(client, "%sTables have been created.", STORE_PREFIX_CONSOLE);
	AskConfirmItemsData(client);
}

public void OnCreateTable(Handle db, Handle results, const char[] error, any data) {
	
}

void AskConfirmItemsData(int client = 0) {
	PrintToChat(client, "%sImport the items now? - (yes, no)", STORE_PREFIX_CONSOLE);
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
	PrintToChat(client, "%sClearing tables...", STORE_PREFIX_CONSOLE);

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
	PrintToChat(client, "%sTables have been cleared successfully.", STORE_PREFIX_CONSOLE);
	AskConfirmItemsData(client);
}

public void OnFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	int client = data;
	PrintToChat(client, "%sError while clearing table %i/%i: %s", STORE_PREFIX_CONSOLE, failIndex, numQueries, error);
	EndInstallation(client);
}

void ImportItemsData(Handle db, int client = 0) {
	char file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), "configs/stores/json-import/");

	DirectoryListing dir = OpenDirectory(file);

	if (dir == null)
	{
		PrintToChat(client, "%sError while importing items data: Can't find folder: %s", STORE_PREFIX_CONSOLE, file);
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
		PrintToChat(client, "%sError while importing items config: Can't open file: %s", STORE_PREFIX_CONSOLE, config);
		return;
	}

	if (file == null) {
		PrintToChat(client, "%sError while importing items config: Can't open file: %s", STORE_PREFIX_CONSOLE, config);
		return;
	}

	CloseHandle(file);

	JSON_Object obj = json_read_from_file(config);

	if (obj == null) {
		PrintToChat(client, "%sError while importing items config: Corrupted JSON: %s", STORE_PREFIX_CONSOLE, config);
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
	CloseHandle(categories);


	char query[4096];
	Transaction trans = SQL_CreateTransaction();

	for (int i = 0; i < numQueries; i++) {
		int category_id = SQL_GetInsertId(results[i]);
		JSON_Array items = view_as<JSON_Array>(queryData[i]);

		for (int x = 0; x < items.Length; x++) {
			JSON_Object item = items.GetObject(i);

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

			int price = item.GetInt("price");

			JSON_Object attrs = item.GetObject("attrs");

			char sattrs[512];
			attrs.Encode(sattrs, sizeof(sattrs));

			bool is_buyable = item.GetBool("is_buyable");
			bool is_tradeable = item.GetBool("is_tradeable");
			bool is_refundable = item.GetBool("is_refundable");
			int expiry_time = item.GetInt("expiry_time");

			char flags[64];
			item.GetString("flags", flags, sizeof(flags));

			FormatEx(query, sizeof(query), "INSERT INTO `store_items` (name, display_name, description, type, loadout_slot, price, category_id, attrs, is_buyable, is_tradeable, is_refundable, expiry_time, flags) VALUES ('%s', '%s', '%s', '%s', '%s', '%i', '%i', '%s', '%i', '%i', '%i', '%i', '%s');", name, display_name, description, type, loadout_slot, price, category_id, attrs, is_buyable, is_tradeable, is_refundable, expiry_time, flags);
			trans.AddQuery(query);
		}

		items.Cleanup();
		CloseHandle(items);
	}

	SQL_ExecuteTransaction(db, trans, OnSuccess3, OnFailure3);
}

public void OnFailure2(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	JSON_Object categories = view_as<JSON_Object>(data);	
	categories.Cleanup();
	CloseHandle(categories);
}

public void OnSuccess3(Database db, any data, int numQueries, Handle[] results, any[] queryData) {

}

public void OnFailure3(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {

}

void EndInstallation(int client = 0, bool success = false) {
	PrintToChat(client, "%sInstall has been completed %s.", STORE_PREFIX_CONSOLE, success ? "successfully" : "unsuccessfully");

	if (success) {
		PrintToChat(client, "%sPlease restart your server.", STORE_PREFIX_CONSOLE);
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
	PrintToChat(client, "%sItem config installs has been completed %s.", STORE_PREFIX_CONSOLE, success ? "successfully" : "unsuccessfully");

	if (success) {
		PrintToChat(client, "%sPlease restart your server.", STORE_PREFIX_CONSOLE);
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