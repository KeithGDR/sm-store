#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <store>

#undef REQUIRE_EXTENSIONS
#include <tf2_stocks>

char TF2_ClassName[TFClassType][] = {"", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer" };

Handle g_clientLoadoutChangedForward;
char g_menuCommands[32][32];

int g_iMenuCommandCount;

char g_game[STORE_MAX_LOADOUTGAME_LENGTH];

int g_clientLoadout[MAXPLAYERS+1];
Handle g_lastClientLoadout;

bool g_databaseInitialized = false;

/**
 * Called before plugin is loaded.
 * 
 * @param myself    The plugin handle.
 * @param late      True if the plugin was loaded after map change, false on map start.
 * @param error     Error message if load failed.
 * @param err_max   Max length of the error message.
 *
 * @return          APLRes_Success for load success, APLRes_Failure or APLRes_SilentFailure otherwise.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Store_OpenLoadoutMenu", Native_OpenLoadoutMenu);
	CreateNative("Store_GetClientLoadout", Native_GetClientLoadout);
	
	RegPluginLibrary("store-loadout");	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name        = "[Store] Loadout",
	author      = "alongub",
	description = "Loadout component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/alongubkin/store"
};


/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	LoadConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	Store_AddMainMenuItem("Loadout", "Loadout Description", _, OnMainMenuLoadoutClick, 10);
	
	g_clientLoadoutChangedForward = CreateGlobalForward("Store_OnClientLoadoutChanged", ET_Event, Param_Cell);
	g_lastClientLoadout = RegClientCookie("lastClientLoadout", "Client loadout", CookieAccess_Protected);
	
	GetGameFolderName(g_game, sizeof(g_game));
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	RegConsoleCmd("sm_loadout", Command_OpenLoadout);

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
}

/**
 * The map is starting.
 */
public void OnMapStart()
{
	if (g_databaseInitialized)
	{
		Store_GetLoadouts(null, INVALID_FUNCTION, false);
	}
}

/**
 * The database is ready to use.
 */
public void Store_OnDatabaseInitialized()
{
	g_databaseInitialized = true;
	Store_GetLoadouts(null, INVALID_FUNCTION, false);
}

/**
 * Called once a client's saved cookies have been loaded from the database.
 */
public void OnClientCookiesCached(int client)
{
	char buffer[12];
	GetClientCookie(client, g_lastClientLoadout, buffer, sizeof(buffer));
	
	g_clientLoadout[client] = StringToInt(buffer);
}

/**
 * Load plugin config.
 */
void LoadConfig() 
{
	Handle kv = CreateKeyValues("root");
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/loadout.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	char menuCommands[255];
	KvGetString(kv, "loadout_commands", menuCommands, sizeof(menuCommands));

	g_iMenuCommandCount = ExplodeString(menuCommands, " ", g_menuCommands, sizeof(g_menuCommands), sizeof(g_menuCommands[]));
	
	CloseHandle(kv);
}

/**
 * Called when a client has typed a message to the chat.
 *
 * @param client		Client index.
 * @param command		Command name, lower case.
 * @param args          Argument count. 
 *
 * @return				Action to take.
 */
public Action Command_Say(int client, const char[] command, int args)
{
	if (0 < client <= MaxClients && !IsClientInGame(client)) 
		return Plugin_Continue;   
	
	char text[256];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	
	for (int index = 0; index < g_iMenuCommandCount; index++) 
	{
		if (StrEqual(g_menuCommands[index], text))
		{
			OpenLoadoutMenu(client);
			
			if (text[0] == 0x2F)
				return Plugin_Handled;
			
			return Plugin_Continue;
		}        
	}
	
	return Plugin_Continue;
}

public Action Command_OpenLoadout(int client, int args)
{
	OpenLoadoutMenu(client);
	return Plugin_Handled;
}

public void OnMainMenuLoadoutClick(int client, const char[] value)
{
	OpenLoadoutMenu(client);
}

public void Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_clientLoadout[client] == 0 || !IsLoadoutAvailableFor(client, g_clientLoadout[client]))
		FindOptimalLoadoutFor(client);
}

/**
 * Opens the loadout menu for a client.
 *
 * @param client			Client index.
 *
 * @noreturn
 */
void OpenLoadoutMenu(int client)
{
	Handle filter = CreateTrie();
	SetTrieString(filter, "game", g_game);
	SetTrieValue(filter, "team", GetClientTeam(client));
	
	if (StrEqual(g_game, "tf"))
	{
		char className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		
		SetTrieString(filter, "class", className);
	}
	
	Store_GetLoadouts(filter, GetLoadoutsCallback, true, client);
}

public void GetLoadoutsCallback(int[] ids, int count, any client)
{
	Handle menu = CreateMenu(LoadoutMenuSelectHandle);
	SetMenuTitle(menu, "Loadout\n \n");
		
	for (int loadout = 0; loadout < count; loadout++)
	{
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetLoadoutDisplayName(ids[loadout], displayName, sizeof(displayName));
		
		char itemText[sizeof(displayName) + 3];
		
		if (g_clientLoadout[client] == ids[loadout])
			strcopy(itemText, sizeof(itemText), "[L] ");
			
		Format(itemText, sizeof(itemText), "%s%s", itemText, displayName);
		
		char itemValue[8];
		IntToString(ids[loadout], itemValue, sizeof(itemValue));
		
		AddMenuItem(menu, itemValue, itemText);
	}
	
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int LoadoutMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char loadoutId[12];
		
		if (GetMenuItem(menu, slot, loadoutId, sizeof(loadoutId)))
		{
			g_clientLoadout[client] = StringToInt(loadoutId);			
			SetClientCookie(client, g_lastClientLoadout, loadoutId);
			
			Call_StartForward(g_clientLoadoutChangedForward);
			Call_PushCell(client);
			Call_Finish();
		}
		
		OpenLoadoutMenu(client);
	}
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_ExitBack)
		{
			Store_OpenMainMenu(client);
		}
	}		
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

bool IsLoadoutAvailableFor(int client, int loadout)
{
	char game[STORE_MAX_LOADOUTGAME_LENGTH];
	Store_GetLoadoutGame(loadout, game, sizeof(game));
	
	if (!StrEqual(game, "") && !StrEqual(game, g_game))
		return false;
	
	if (StrEqual(g_game, "tf"))
	{
		char loadoutClass[STORE_MAX_LOADOUTCLASS_LENGTH];
		Store_GetLoadoutClass(loadout, loadoutClass, sizeof(loadoutClass));
		
		char className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		
		if (!StrEqual(loadoutClass, "") && !StrEqual(loadoutClass, className))
			return false;		
	}
	
	int loadoutTeam = Store_GetLoadoutTeam(loadout);
	if (loadoutTeam != -1 && GetClientTeam(client) != loadoutTeam)
		return false;
		
	return true;
}

void FindOptimalLoadoutFor(int client)
{
	if (!g_databaseInitialized)
		return;
		
	Handle filter = CreateTrie();
	SetTrieString(filter, "game", g_game);
	SetTrieValue(filter, "team", GetClientTeam(client));
	
	if (StrEqual(g_game, "tf"))
	{
		char className[10];
		TF2_GetClassName(TF2_GetPlayerClass(client), className, sizeof(className));
		
		SetTrieString(filter, "class", className);
	}
	
	Store_GetLoadouts(filter, FindOptimalLoadoutCallback, true, GetClientSerial(client));
}

public void FindOptimalLoadoutCallback(int[] ids, int count, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
	
	if (count > 0)
	{
		g_clientLoadout[client] = ids[0];
		
		char buffer[12];
		IntToString(g_clientLoadout[client], buffer, sizeof(buffer));
		
		SetClientCookie(client, g_lastClientLoadout, buffer);
		
		Call_StartForward(g_clientLoadoutChangedForward);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		Store_LogWarning("No loadout found.");
	}	
}

public void Native_OpenLoadoutMenu(Handle plugin, int params)
{       
	OpenLoadoutMenu(GetNativeCell(1));
}

public int Native_GetClientLoadout(Handle plugin, int params)
{       
	return g_clientLoadout[GetNativeCell(1)];
}

void TF2_GetClassName(TFClassType classType, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, TF2_ClassName[classType]);
}
