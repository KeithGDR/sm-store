#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colorlib>
#include <store>
#include <json>

#define MAX_COMMANDITEMS 512

enum struct CommandItem
{
	char CommandItemName[STORE_MAX_NAME_LENGTH];
	char CommandItemText[255];
	int CommandItemTeams[5];
}

CommandItem g_commandItems[MAX_COMMANDITEMS];
int g_commandItemCount;

Handle g_commandItemsNameIndex;

public Plugin myinfo =
{
	name        = "[Store] CommandItems",
	author      = "Alongub, KeithGDR",
	description = "CommandItems component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
    LoadTranslations("store.phrases");
    Store_RegisterItemType("commanditem", OnCommandItemUse, OnCommandItemAttributesLoad);
}

/** 
 * Called when a new API library is loaded.
 */
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("commanditem", OnCommandItemUse, OnCommandItemAttributesLoad);
	}	
}

public void Store_OnReloadItems() 
{
	if (g_commandItemsNameIndex != null)
		CloseHandle(g_commandItemsNameIndex);
		
	g_commandItemsNameIndex = CreateTrie();
	g_commandItemCount = 0;
}

public void OnCommandItemAttributesLoad(const char[] itemName, const char[] attrs)
{
	strcopy(g_commandItems[g_commandItemCount].CommandItemName, STORE_MAX_NAME_LENGTH, itemName);
		
	SetTrieValue(g_commandItemsNameIndex, g_commandItems[g_commandItemCount].CommandItemName, g_commandItemCount);
	
	JSON_Object json = json_decode(attrs);
	json.GetString("command", g_commandItems[g_commandItemCount].CommandItemText, 255);

	JSON_Array teams = view_as<JSON_Array>(json.GetObject("teams"));

	for (int i = 0, size = teams.Length; i < size; i++)
		g_commandItems[g_commandItemCount].CommandItemTeams[i] = teams.GetInt(i);

	CloseHandle(teams);
	CloseHandle(json);

	g_commandItemCount++;
}

public Store_ItemUseAction OnCommandItemUse(int client, int itemId, bool equipped)
{
	if (!IsClientInGame(client))
	{
		return Store_DoNothing;
	}

	char itemName[STORE_MAX_NAME_LENGTH];
	Store_GetItemName(itemId, itemName, sizeof(itemName));

	int commandItem = -1;
	if (!GetTrieValue(g_commandItemsNameIndex, itemName, commandItem))
	{
		Store_PrintToChat(client, "%t", "No item attributes");
		return Store_DoNothing;
	}

	int clientTeam = GetClientTeam(client);

	bool teamAllowed = false;
	for (int teamIndex = 0; teamIndex < 5; teamIndex++)
	{
		if (g_commandItems[commandItem].CommandItemTeams[teamIndex] == clientTeam)
		{
			teamAllowed = true;
			break;
		}
	}

	if (!teamAllowed)
	{
		return Store_DoNothing;
	}

	char clientName[64];
	GetClientName(client, clientName, sizeof(clientName));

	char clientTeamStr[13];
	IntToString(clientTeam, clientTeamStr, sizeof(clientTeamStr));

	char clientAuth[32];
	GetClientAuthId(client, AuthId_Engine, clientAuth, sizeof(clientAuth));

	char clientUser[11];
	Format(clientUser, sizeof(clientUser), "#%d", GetClientUserId(client));

	char commandText[255];
	strcopy(commandText, sizeof(commandText), g_commandItems[commandItem].CommandItemText);

	ReplaceString(commandText, sizeof(commandText), "{clientName}", clientName, false);
	ReplaceString(commandText, sizeof(commandText), "{clientTeam}", clientTeamStr, false);		
	ReplaceString(commandText, sizeof(commandText), "{clientAuth}", clientAuth, false);
	ReplaceString(commandText, sizeof(commandText), "{clientUser}", clientUser, false);		

	ServerCommand(commandText);
	return Store_DeleteItem;
}