#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <store>
#include <scp>
#include <json>
#include <colorlib>

enum struct Title
{
	char TitleName[STORE_MAX_NAME_LENGTH];
	char TitleText[64];
}

Title g_titles[1024];
int g_titleCount = 0;

int g_clientTitles[MAXPLAYERS+1];

Handle g_titlesNameIndex = null;
bool g_databaseInitialized = false;

public Plugin myinfo =
{
	name        = "[Store] Titles",
	author      = "Alongub, KeithGDR",
	description = "Titles component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	Store_RegisterItemType("title", OnEquip, LoadItem);
}

/** 
 * Called when a new API library is loaded.
 */
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("title", OnEquip, LoadItem);
	}	
}

public void Store_OnDatabaseInitialized()
{
	g_databaseInitialized = true;
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
	if (!g_databaseInitialized)
		return;
		
	g_clientTitles[client] = -1;
	Store_GetEquippedItemsByType(GetSteamAccountID(client), "title", Store_GetClientLoadout(client), OnGetPlayerTitle, GetClientSerial(client));
}

public void Store_OnClientLoadoutChanged(int client)
{
	g_clientTitles[client] = -1;
	Store_GetEquippedItemsByType(GetSteamAccountID(client), "title", Store_GetClientLoadout(client), OnGetPlayerTitle, GetClientSerial(client));
}

public void Store_OnReloadItems() 
{
	if (g_titlesNameIndex != null)
		CloseHandle(g_titlesNameIndex);
		
	g_titlesNameIndex = CreateTrie();
	g_titleCount = 0;
}

public void OnGetPlayerTitle(int[] titles, int count, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	for (int index = 0; index < count; index++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(titles[index], itemName, sizeof(itemName));
		
		int title = -1;
		if (!GetTrieValue(g_titlesNameIndex, itemName, title))
		{
			Store_PrintToChat(client, "%t", "No item attributes");
			continue;
		}
		
		g_clientTitles[client] = title;
		break;
	}
}

public void LoadItem(const char[] itemName, const char[] attrs)
{
	strcopy(g_titles[g_titleCount].TitleName, STORE_MAX_NAME_LENGTH, itemName);
		
	SetTrieValue(g_titlesNameIndex, g_titles[g_titleCount].TitleName, g_titleCount);
	
	JSON_Object json = json_decode(attrs);	

	if (IsSource2009())
	{
		json.GetString("colorful_text", g_titles[g_titleCount].TitleText, 64);
		CFormat(g_titles[g_titleCount].TitleText, 64);
	}
	else
	{
		json.GetString("text", g_titles[g_titleCount].TitleText, 64);
		CFormat(g_titles[g_titleCount].TitleText, 64);
	}

	CloseHandle(json);

	g_titleCount++;
}

public Store_ItemUseAction OnEquip(int client, int itemId, bool equipped)
{
	char name[32];
	Store_GetItemName(itemId, name, sizeof(name));

	if (equipped)
	{
		g_clientTitles[client] = -1;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		Store_PrintToChat(client, "%t", "Unequipped item", displayName);

		return Store_UnequipItem;
	}
	else
	{
		int title = -1;
		if (!GetTrieValue(g_titlesNameIndex, name, title))
		{
			Store_PrintToChat(client, "%t", "No item attributes");
			return Store_DoNothing;
		}
		
		g_clientTitles[client] = title;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		Store_PrintToChat(client, "%t", "Equipped item", displayName);

		return Store_EquipItem;
	}
}

public Action OnChatMessage(int &author, Handle recipients, char[] name, char[] message)
{
	if (g_clientTitles[author] != -1)
	{
		Format(name, MAXLENGTH_NAME, "%s\x03 %s", g_titles[g_clientTitles[author]].TitleText, name);		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

bool IsSource2009()
{
	if (GetEngineVersion() == Engine_CSS || GetEngineVersion() == Engine_HL2DM || GetEngineVersion() == Engine_DODS || GetEngineVersion() == Engine_TF2)
		return true;
	
	return false;
}