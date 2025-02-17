#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <store>
#include <json>
#include <smartdm>

enum struct Skin
{
	char SkinName[STORE_MAX_NAME_LENGTH];
	char SkinModelPath[PLATFORM_MAX_PATH]; 
	int SkinTeams[5];
}

Skin g_skins[1024];
int g_skinCount = 0;

Handle g_skinNameIndex;

char g_game[32];

public Plugin myinfo =
{
    name        = "[Store] Skins",
    author      = "Alongub, KeithGDR",
    description = "Skins component for [Store]",
    version     = STORE_VERSION,
    url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	LoadTranslations("store.phrases");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	Store_RegisterItemType("skin", OnEquip, LoadItem);
	GetGameFolderName(g_game, sizeof(g_game));
}

/**
 * Map is starting
 */
public void OnMapStart()
{
	for (int skin = 0; skin < g_skinCount; skin++)
	{
		if (strcmp(g_skins[skin].SkinModelPath, "") != 0 && (FileExists(g_skins[skin].SkinModelPath) || FileExists(g_skins[skin].SkinModelPath, true)))
		{
			PrecacheModel(g_skins[skin].SkinModelPath);
			Downloader_AddFileToDownloadsTable(g_skins[skin].SkinModelPath);
		}
	}
}

/** 
 * Called when a new API library is loaded.
 */
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("skin", OnEquip, LoadItem);
	}
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientInGame(client))
		return Plugin_Continue;

	if (IsFakeClient(client))
		return Plugin_Continue;

	CreateTimer(1.0, Timer_Spawn, GetClientSerial(client));
	
	return Plugin_Continue;
}

public Action Timer_Spawn(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return Plugin_Continue;
		
	Store_GetEquippedItemsByType(GetSteamAccountID(client), "skin", Store_GetClientLoadout(client), OnGetPlayerSkin, serial);
	
	return Plugin_Continue;
}

public void Store_OnClientLoadoutChanged(int client)
{
	Store_GetEquippedItemsByType(GetSteamAccountID(client), "skin", Store_GetClientLoadout(client), OnGetPlayerSkin, GetClientSerial(client));
}

public void OnGetPlayerSkin(int[] ids, int count, any serial)
{
	int client = GetClientFromSerial(serial);

	if (client == 0)
		return;
		
	if (!IsClientInGame(client))
		return;
	
	if (!IsPlayerAlive(client))
		return;
	
	int team = GetClientTeam(client);
	for (int index = 0; index < count; index++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(ids[index], itemName, sizeof(itemName));
		
		int skin = -1;
		if (!GetTrieValue(g_skinNameIndex, itemName, skin))
		{
			PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
			continue;
		}

		bool teamAllowed = false;
		for (int teamIndex = 0; teamIndex < 5; teamIndex++)
		{
			if (g_skins[skin].SkinTeams[teamIndex] == team)
			{
				teamAllowed = true;
				break;
			}
		}


		if (!teamAllowed)
		{
			continue;
		}

		if (StrEqual(g_game, "tf"))
		{
			SetVariantString(g_skins[skin].SkinModelPath);
			AcceptEntityInput(client, "SetCustomModel");
			SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
		}
		else
		{
			SetEntityModel(client, g_skins[skin].SkinModelPath);
		}
	}
}

public void Store_OnReloadItems() 
{
	if (g_skinNameIndex != null)
		CloseHandle(g_skinNameIndex);
		
	g_skinNameIndex = CreateTrie();
	g_skinCount = 0;
}

public void LoadItem(const char[] itemName, const char[] attrs)
{
	strcopy(g_skins[g_skinCount].SkinName, STORE_MAX_NAME_LENGTH, itemName);

	SetTrieValue(g_skinNameIndex, g_skins[g_skinCount].SkinName, g_skinCount);

	JSON_Object json = json_decode(attrs);
	json.GetString("model", g_skins[g_skinCount].SkinModelPath, PLATFORM_MAX_PATH);

	if (strcmp(g_skins[g_skinCount].SkinModelPath, "") != 0 && (FileExists(g_skins[g_skinCount].SkinModelPath) || FileExists(g_skins[g_skinCount].SkinModelPath, true)))
	{
		PrecacheModel(g_skins[g_skinCount].SkinModelPath);
		Downloader_AddFileToDownloadsTable(g_skins[g_skinCount].SkinModelPath);
	}

	JSON_Array teams = view_as<JSON_Array>(json.GetObject("teams"));

	for (int i = 0, size = teams.Length; i < size; i++)
		g_skins[g_skinCount].SkinTeams[i] = teams.GetInt(i);

	CloseHandle(json);

	g_skinCount++;
}

public Store_ItemUseAction OnEquip(int client, int itemId, bool equipped)
{
	if (equipped)
		return Store_UnequipItem;
	
	PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item apply next spawn");
	return Store_EquipItem;
}