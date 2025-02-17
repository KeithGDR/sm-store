#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <store>

#include <colorlib>

#define MAX_MENU_ITEMS	32

enum struct MenuItem
{
	char MenuItemDisplayName[32];
	char MenuItemDescription[128];
	char MenuItemValue[64];
	Handle MenuItemPlugin;
	Function MenuItemCallback;
	int MenuItemOrder;
}

char g_currencyName[64];
char g_menuCommands[32][32];
char g_creditsCommand[32];

int g_iMenuCommandCount;

MenuItem g_menuItems[MAX_MENU_ITEMS + 1];
int g_menuItemCount = 0;

int g_firstConnectionCredits = 0;

bool g_allPluginsLoaded = false;

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
	CreateNative("Store_OpenMainMenu", Native_OpenMainMenu);
	CreateNative("Store_AddMainMenuItem", Native_AddMainMenuItem);
	CreateNative("Store_GetCurrencyName", Native_GetCurrencyName);

	RegPluginLibrary("store");	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name        = "[Store] Core",
	author      = "alongub",
	description = "Core component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/alongubkin/store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	CreateConVar("store_version", STORE_VERSION, "Store Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

	LoadConfig();
	
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	RegConsoleCmd("sm_store", Command_OpenMainMenu);
	RegConsoleCmd(g_creditsCommand, Command_Credits);

	RegAdminCmd("store_givecredits", Command_GiveCredits, ADMFLAG_ROOT, "Gives credits to a player.");

	g_allPluginsLoaded = false;
}

/**
 * All plugins have been loaded.
 */
public void OnAllPluginsLoaded()
{
	SortMainMenuItems();
	g_allPluginsLoaded = true;
}

/**
 * Called once a client is authorized and fully in-game, and 
 * after all post-connection authorizations have been performed.  
 *
 * This callback is gauranteed to occur on all clients, and always 
 * after each OnClientPutInServer() call.
 *
 * @param client		Client index.
 * @noreturn
 */
public void OnClientPostAdminCheck(int client)
{	
	Store_RegisterClient(client, g_firstConnectionCredits);
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
			OpenMainMenu(client);
			
			if (text[0] == 0x2F)
				return Plugin_Handled;
			
			return Plugin_Continue;
		}        
	}
	
	return Plugin_Continue;
}

public Action Command_OpenMainMenu(int client, int args)
{
	OpenMainMenu(client);
	return Plugin_Handled;
}

public Action Command_Credits(int client, int args)
{
	Store_GetCredits(GetSteamAccountID(client), OnCommandGetCredits, client);
	return Plugin_Handled;
}

public Action Command_GiveCredits(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "%sUsage: store_givecredits <name> <credits>", STORE_PREFIX);
		return Plugin_Handled;
	}
    
	char target[65];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;
    
	GetCmdArg(1, target, sizeof(target));
    
	char money[32];
	GetCmdArg(2, money, sizeof(money));
    
	int imoney = StringToInt(money);
 
	if ((target_count = ProcessTargetString(
			target,
			0,
			target_list,
			MAXPLAYERS,
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	int[] accountIds = new int[target_count];
	int count = 0;

	for (int i = 0; i < target_count; i++)
	{
		if (IsClientInGame(target_list[i]) && !IsFakeClient(target_list[i]))
		{
			accountIds[count] = GetSteamAccountID(target_list[i]);
			count++;

			PrintToChat(target_list[i], "%s%t", STORE_PREFIX, "Received Credits", imoney, g_currencyName);
		}
	}

	Store_GiveCreditsToUsers(accountIds, count, imoney);
	return Plugin_Handled;
}

public void OnCommandGetCredits(int credits, any client)
{
	PrintToChat(client, "%s%t", STORE_PREFIX, "Store Menu Title", credits, g_currencyName);
}

/**
 * Load plugin config.
 */
void LoadConfig() 
{
	Handle kv = CreateKeyValues("root");
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/core.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	char menuCommands[255];
	KvGetString(kv, "mainmenu_commands", menuCommands, sizeof(menuCommands));
	g_iMenuCommandCount = ExplodeString(menuCommands, " ", g_menuCommands, sizeof(g_menuCommands), sizeof(g_menuCommands[]));
	
	KvGetString(kv, "currency_name", g_currencyName, sizeof(g_currencyName));
	KvGetString(kv, "credits_command", g_creditsCommand, sizeof(g_creditsCommand), "sm_credits");

	g_firstConnectionCredits = KvGetNum(kv, "first_connection_credits");

	CloseHandle(kv);
}

/**
 * Adds an item to the main menu. 
 *
 * @param displayName		The text of the item, as it is shown to the player.
 * @param description		A short description of the item.
 * @param value				Item information string that will be sent to the callback.
 * @param plugin			The plugin owner of the callback.
 * @param callback			Callback to the item click event.
 * @param order				Preferred position of the item in the menu.
 *
 * @noreturn
 */ 
void AddMainMenuItem(const char[] displayName, const char[] description = "", const char[] value = "", Handle plugin = INVALID_HANDLE, Function callback, int order = 32)
{
	int item;
	
	for (; item <= g_menuItemCount; item++)
	{
		if (item == g_menuItemCount || StrEqual(g_menuItems[item].MenuItemDisplayName, displayName))
			break;
	}
	
	strcopy(g_menuItems[item].MenuItemDisplayName, 32, displayName);
	strcopy(g_menuItems[item].MenuItemDescription, 128, description);
	strcopy(g_menuItems[item].MenuItemValue, 64, value);   
	g_menuItems[item].MenuItemPlugin = plugin;
	g_menuItems[item].MenuItemCallback = callback;
	g_menuItems[item].MenuItemOrder = order;

	if (item == g_menuItemCount)
		g_menuItemCount++;
	
	if (g_allPluginsLoaded)
		SortMainMenuItems();
}

/**
 * Sort menu items by their preffered order.
 *
 * @noreturn
 */ 
void SortMainMenuItems()
{
	int sortIndex = sizeof(g_menuItems) - 1;
	
	for (int x = 0; x < g_menuItemCount; x++) 
	{
		for (int y = 0; y < g_menuItemCount; y++) 
		{
			if (g_menuItems[x].MenuItemOrder < g_menuItems[y].MenuItemOrder)
			{
				g_menuItems[sortIndex] = g_menuItems[x];
				g_menuItems[x] = g_menuItems[y];
				g_menuItems[y] = g_menuItems[sortIndex];
			}
		}
	}
}

/**
 * Opens the main menu for a player.
 *
 * @param client		Client Index
 *
 * @noreturn
 */
void OpenMainMenu(int client)
{	
	Store_GetCredits(GetSteamAccountID(client), OnGetCreditsComplete, GetClientSerial(client));
}

public void OnGetCreditsComplete(int credits, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	Handle menu = CreateMenu(MainMenuSelectHandle);
	SetMenuTitle(menu, "%T\n \n", "Store Menu Title", client, credits, g_currencyName);
	
	for (int item = 0; item < g_menuItemCount; item++)
	{
		char text[255];  
		Format(text, sizeof(text), "%T\n%T", g_menuItems[item].MenuItemDisplayName, client, g_menuItems[item].MenuItemDescription, client);
				
		AddMenuItem(menu, g_menuItems[item].MenuItemValue, text);
	}
	
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int MainMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			Call_StartFunction(g_menuItems[slot].MenuItemPlugin, g_menuItems[slot].MenuItemCallback);
			Call_PushCell(client);
			Call_PushString(g_menuItems[slot].MenuItemValue);
			Call_Finish();
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}

	return 0;
}

public void Native_OpenMainMenu(Handle plugin, int params)
{       
	OpenMainMenu(GetNativeCell(1));
}

public void Native_AddMainMenuItem(Handle plugin, int params)
{
	char displayName[32];
	GetNativeString(1, displayName, sizeof(displayName));
	
	char description[128];
	GetNativeString(2, description, sizeof(description));
	
	char value[64];
	GetNativeString(3, value, sizeof(value));
	
	AddMainMenuItem(displayName, description, value, plugin, GetNativeFunction(4), GetNativeCell(5));
}

public void Native_GetCurrencyName(Handle plugin, int params)
{       
	SetNativeString(1, g_currencyName, GetNativeCell(2));
}
