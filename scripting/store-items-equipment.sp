#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smartdm>
#include <store>
#include <json>

#undef REQUIRE_PLUGIN
#include <ToggleEffects>
#include <zombiereloaded>

enum struct Equipment
{
	char EquipmentName[STORE_MAX_NAME_LENGTH];
	char EquipmentModelPath[PLATFORM_MAX_PATH]; 
	float EquipmentPosition[3];
	float EquipmentAngles[3];
	char EquipmentFlag[2];
	char EquipmentAttachment[32];
}

enum struct EquipmentPlayerModelSettings
{
	char EquipmentName[STORE_MAX_NAME_LENGTH];
	char PlayerModelPath[PLATFORM_MAX_PATH];
	float Position[3];
	float Angles[3];
}

Handle g_hLookupAttachment = null;

bool g_zombieReloaded;
bool g_toggleEffects;

Equipment g_equipment[1024];
int g_equipmentCount = 0;

Handle g_equipmentNameIndex = null;
Handle g_loadoutSlotList = null;

EquipmentPlayerModelSettings g_playerModels[1024];
int g_playerModelCount = 0;

int g_iEquipment[MAXPLAYERS+1][32];

public Plugin myinfo =
{
	name        = "[Store] Equipment",
	author      = "Alongub, KeithGDR",
	description = "Equipment component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

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
	MarkNativeAsOptional("ZR_IsClientHuman"); 
	MarkNativeAsOptional("ZR_IsClientZombie"); 

	return APLRes_Success;
}

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");
	
	g_loadoutSlotList = CreateArray(ByteCountToCells(32));
	
	g_zombieReloaded = LibraryExists("zombiereloaded");
	g_toggleEffects = LibraryExists("ToggleEffects");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	Handle hGameConf = LoadGameConfigFile("store-equipment.gamedata");
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "LookupAttachment");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	g_hLookupAttachment = EndPrepSDKCall();	

	Store_RegisterItemType("equipment", OnEquip, LoadItem);
}

/**
 * Map is starting
 */
public void OnMapStart()
{
	for (int item = 0; item < g_equipmentCount; item++)
	{
		if (strcmp(g_equipment[item].EquipmentModelPath, "") != 0 && (FileExists(g_equipment[item].EquipmentModelPath) || FileExists(g_equipment[item].EquipmentModelPath, true)))
		{
			PrecacheModel(g_equipment[item].EquipmentModelPath);
			Downloader_AddFileToDownloadsTable(g_equipment[item].EquipmentModelPath);
		}
	}
}

/** 
 * Called when a new API library is loaded.
 */
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_zombieReloaded = true;
	}
	else if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("equipment", OnEquip, LoadItem);
	}
}

/** 
 * Called when an API library is removed.
 */
public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "zombiereloaded"))
	{
		g_zombieReloaded = false;
	}
}

public void OnClientDisconnect(int client)
{
	UnequipAll(client);
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!g_zombieReloaded || (g_zombieReloaded && ZR_IsClientHuman(client)))
		CreateTimer(1.0, SpawnTimer, GetClientSerial(client));
	else
		UnequipAll(client);
	
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	UnequipAll(GetClientOfUserId(GetEventInt(event, "userid")));
	return Plugin_Continue;
}

/**
 * Called after a player has become a zombie.
 * 
 * @param client            The client that was infected.
 * @param attacker          The the infecter. (-1 if there is no infecter)
 * @param motherInfect      If the client is a mother zombie.
 * @param respawnOverride   True if the respawn cvar was overridden.
 * @param respawn           The value that respawn was overridden with.
 */
public int ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
	UnequipAll(client);
}

/**
 * Called right before ZR is about to respawn a player.
 * Here you can modify any variable or stop the action entirely.
 * 
 * @param client            The client index.
 * @param condition         Respawn condition. See ZR_RespawnCondition for
 *                          details.
 *
 * @return      Plugin_Handled to block respawn.
 */
public int ZR_OnClientRespawned(int client, ZR_RespawnCondition condition)
{
	UnequipAll(client);
}

public Action SpawnTimer(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return Plugin_Continue;
	
	if (g_zombieReloaded && !ZR_IsClientHuman(client))
		return Plugin_Continue;
		
	Store_GetEquippedItemsByType(GetSteamAccountID(client), "equipment", Store_GetClientLoadout(client), OnGetPlayerEquipment, serial);
	return Plugin_Continue;
}

public void Store_OnClientLoadoutChanged(int client)
{
	Store_GetEquippedItemsByType(GetSteamAccountID(client), "equipment", Store_GetClientLoadout(client), OnGetPlayerEquipment, GetClientSerial(client));
}

public void Store_OnReloadItems() 
{
	if (g_equipmentNameIndex != null)
		CloseHandle(g_equipmentNameIndex);
		
	g_equipmentNameIndex = CreateTrie();
	g_equipmentCount = 0;
}

public void LoadItem(const char[] itemName, const char[] attrs)
{
	strcopy(g_equipment[g_equipmentCount].EquipmentName, STORE_MAX_NAME_LENGTH, itemName);

	SetTrieValue(g_equipmentNameIndex, g_equipment[g_equipmentCount].EquipmentName, g_equipmentCount);

	JSON_Object json = json_decode(attrs);
	json.GetString("model", g_equipment[g_equipmentCount].EquipmentModelPath, PLATFORM_MAX_PATH);
	json.GetString("attachment", g_equipment[g_equipmentCount].EquipmentAttachment, 32);

	JSON_Array position = view_as<JSON_Array>(json.GetObject("position"));

	for (int i = 0; i <= 2; i++)
		g_equipment[g_equipmentCount].EquipmentPosition[i] = position.GetFloat(i);

	CloseHandle(position);

	JSON_Array angles = view_as<JSON_Array>(json.GetObject("angles"));

	for (int i = 0; i <= 2; i++)
		g_equipment[g_equipmentCount].EquipmentAngles[i] = angles.GetFloat(i);

	CloseHandle(angles);

	if (strcmp(g_equipment[g_equipmentCount].EquipmentModelPath, "") != 0 && (FileExists(g_equipment[g_equipmentCount].EquipmentModelPath) || FileExists(g_equipment[g_equipmentCount].EquipmentModelPath, true)))
	{
		PrecacheModel(g_equipment[g_equipmentCount].EquipmentModelPath);
		Downloader_AddFileToDownloadsTable(g_equipment[g_equipmentCount].EquipmentModelPath);
	}

	JSON_Array playerModels = view_as<JSON_Array>(json.GetObject("playermodels"));

	if (playerModels != null && playerModels.IsArray)
	{
		for (int index = 0, size = playerModels.Length; index < size; index++)
		{
			JSON_Object playerModel = playerModels.GetObject(index);

			if (playerModel == null)
				continue;

			if (playerModels.GetType(index) != JSON_Type_Object)
				continue;

			playerModel.GetString("playermodel", g_playerModels[g_playerModelCount].PlayerModelPath, PLATFORM_MAX_PATH);

			JSON_Array playerModelPosition = view_as<JSON_Array>(playerModel.GetObject("position"));

			for (int i = 0; i <= 2; i++)
				g_playerModels[g_playerModelCount].Position[i] = playerModelPosition.GetFloat(i);

			CloseHandle(playerModelPosition);

			JSON_Array playerModelAngles = view_as<JSON_Array>(playerModel.GetObject("angles"));

			for (int i = 0; i <= 2; i++)
				g_playerModels[g_playerModelCount].Angles[i] = playerModelAngles.GetFloat(i);

			strcopy(g_playerModels[g_playerModelCount].EquipmentName, STORE_MAX_NAME_LENGTH, itemName);

			CloseHandle(playerModelAngles);
			CloseHandle(playerModel);

			g_playerModelCount++;
		}

		CloseHandle(playerModels);
	}

	CloseHandle(json);

	g_equipmentCount++;
}

public void OnGetPlayerEquipment(int[] ids, int count, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	if (!IsClientInGame(client))
		return;
	
	if (!IsPlayerAlive(client))
		return;
		
	for (int index = 0; index < count; index++)
	{
		char itemName[STORE_MAX_NAME_LENGTH];
		Store_GetItemName(ids[index], itemName, sizeof(itemName));
		
		char loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
		Store_GetItemLoadoutSlot(ids[index], loadoutSlot, sizeof(loadoutSlot));
		
		int loadoutSlotIndex = FindStringInArray(g_loadoutSlotList, loadoutSlot);
		
		if (loadoutSlotIndex == -1)
			loadoutSlotIndex = PushArrayString(g_loadoutSlotList, loadoutSlot);
		
		Unequip(client, loadoutSlotIndex);
		
		if (!g_zombieReloaded || (g_zombieReloaded && ZR_IsClientHuman(client)))
			Equip(client, loadoutSlotIndex, itemName);
	}
}

public Store_ItemUseAction OnEquip(int client, int itemId, bool equipped)
{
	if (!IsClientInGame(client))
	{
		return Store_DoNothing;
	}
	
	if (!IsPlayerAlive(client))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Must be alive to equip");
		return Store_DoNothing;
	}
	
	if (g_zombieReloaded && !ZR_IsClientHuman(client))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Must be human to equip");	
		return Store_DoNothing;
	}
	
	char name[STORE_MAX_NAME_LENGTH];
	Store_GetItemName(itemId, name, sizeof(name));
	
	char loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
	Store_GetItemLoadoutSlot(itemId, loadoutSlot, sizeof(loadoutSlot));
	
	int loadoutSlotIndex = FindStringInArray(g_loadoutSlotList, loadoutSlot);
	
	if (loadoutSlotIndex == -1)
		loadoutSlotIndex = PushArrayString(g_loadoutSlotList, loadoutSlot);
		
	if (equipped)
	{
		if (!Unequip(client, loadoutSlotIndex))
			return Store_DoNothing;
	
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Unequipped item", displayName);
		return Store_UnequipItem;
	}
	else
	{
		if (!Equip(client, loadoutSlotIndex, name))
			return Store_DoNothing;
		
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
		PrintToChat(client, "%s%t", STORE_PREFIX, "Equipped item", displayName);
		return Store_EquipItem;
	}
}

bool Equip(int client, int loadoutSlot, const char[] name)
{
	Unequip(client, loadoutSlot);
		
	int equipment = -1;
	if (!GetTrieValue(g_equipmentNameIndex, name, equipment))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
		return false;
	}
	
	if (!LookupAttachment(client, g_equipment[equipment].EquipmentAttachment)) 
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Player model unsupported");
		return false;
	}
	
	float or[3];
	float ang[3];
	float fForward[3];
	float fRight[3];
	float fUp[3];
	
	GetClientAbsOrigin(client,or);
	GetClientAbsAngles(client,ang);

	char clientModel[PLATFORM_MAX_PATH];
	GetClientModel(client, clientModel, sizeof(clientModel));
	
	int playerModel = -1;
	for (int j = 0; j < g_playerModelCount; j++)
	{	
		if (StrEqual(g_equipment[equipment].EquipmentName, g_playerModels[j].EquipmentName) && StrEqual(clientModel, g_playerModels[j].PlayerModelPath, false))
		{
			playerModel = j;
			break;
		}
	}

	if (playerModel == -1)
	{
		ang[0] += g_equipment[equipment].EquipmentAngles[0];
		ang[1] += g_equipment[equipment].EquipmentAngles[1];
		ang[2] += g_equipment[equipment].EquipmentAngles[2];
	}
	else
	{
		ang[0] += g_playerModels[playerModel].Angles[0];
		ang[1] += g_playerModels[playerModel].Angles[1];
		ang[2] += g_playerModels[playerModel].Angles[2];		
	}

	float fOffset[3];

	if (playerModel == -1)
	{
		fOffset[0] = g_equipment[equipment].EquipmentPosition[0];
		fOffset[1] = g_equipment[equipment].EquipmentPosition[1];
		fOffset[2] = g_equipment[equipment].EquipmentPosition[2];	
	}
	else
	{
		fOffset[0] = g_playerModels[playerModel].Position[0];
		fOffset[1] = g_playerModels[playerModel].Position[1];
		fOffset[2] = g_playerModels[playerModel].Position[2];		
	}
		
	GetAngleVectors(ang, fForward, fRight, fUp);

	or[0] += fRight[0]*fOffset[0]+fForward[0]*fOffset[1]+fUp[0]*fOffset[2];
	or[1] += fRight[1]*fOffset[0]+fForward[1]*fOffset[1]+fUp[1]*fOffset[2];
	or[2] += fRight[2]*fOffset[0]+fForward[2]*fOffset[1]+fUp[2]*fOffset[2];

	int ent = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(ent, "model", g_equipment[equipment].EquipmentModelPath);
	DispatchKeyValue(ent, "spawnflags", "256");
	DispatchKeyValue(ent, "solid", "0");
	SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", client);
	
	DispatchSpawn(ent);	
	AcceptEntityInput(ent, "TurnOn", ent, ent, 0);
	
	g_iEquipment[client][loadoutSlot] = ent;
	
	SDKHook(ent, SDKHook_SetTransmit, ShouldHide);
	
	TeleportEntity(ent, or, ang, NULL_VECTOR); 
	
	SetVariantString("!activator");
	AcceptEntityInput(ent, "SetParent", client, ent, 0);
	
	SetVariantString(g_equipment[equipment].EquipmentAttachment);
	AcceptEntityInput(ent, "SetParentAttachmentMaintainOffset", ent, ent, 0);
	
	return true;
}

bool Unequip(int client, int loadoutSlot)
{      
	if (g_iEquipment[client][loadoutSlot] != 0 && IsValidEdict(g_iEquipment[client][loadoutSlot]))
	{
		SDKUnhook(g_iEquipment[client][loadoutSlot], SDKHook_SetTransmit, ShouldHide);
		AcceptEntityInput(g_iEquipment[client][loadoutSlot], "Kill");
	}
	
	g_iEquipment[client][loadoutSlot] = 0;
	return true;
}

void UnequipAll(int client)
{
	for (int index = 0, size = GetArraySize(g_loadoutSlotList); index < size; index++)
		Unequip(client, index);
}

public Action ShouldHide(int ent, int client)
{
	if (g_toggleEffects)
		if (!ShowClientEffects(client))
			return Plugin_Handled;
			
	for (int index = 0, size = GetArraySize(g_loadoutSlotList); index < size; index++)
	{
		if (ent == g_iEquipment[client][index])
			return Plugin_Handled;
	}
	
	if (IsClientInGame(client) && GetEntProp(client, Prop_Send, "m_iObserverMode") == 4 && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") >= 0)
	{
		for (int index = 0, size = GetArraySize(g_loadoutSlotList); index < size; index++)
		{
			if(ent == g_iEquipment[GetEntPropEnt(client, Prop_Send, "m_hObserverTarget")][index])
				return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

stock bool LookupAttachment(int client, const char[] point)
{
	if (g_hLookupAttachment == null)
		return false;

	if (client <= 0 || !IsClientInGame(client)) 
		return false;
	
	return SDKCall(g_hLookupAttachment, client, point);
}