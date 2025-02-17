#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colorlib>
#include <store>

bool g_hideEmptyCategories = false;

char g_menuCommands[32][32];

Handle g_itemTypes;
Handle g_itemTypeNameIndex;

public Plugin myinfo =
{
	name        = "[Store] Inventory",
	author      = "Alongub, KeithGDR",
	description = "Inventory component for [Store]",
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
	CreateNative("Store_OpenInventory", Native_OpenInventory);
	CreateNative("Store_OpenInventoryCategory", Native_OpenInventoryCategory);
	
	CreateNative("Store_RegisterItemType", Native_RegisterItemType);
	CreateNative("Store_IsItemTypeRegistered", Native_IsItemTypeRegistered);
	
	CreateNative("Store_CallItemAttrsCallback", Native_CallItemAttrsCallback);
	
	RegPluginLibrary("store-inventory");	
	return APLRes_Success;
}

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	LoadConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	Store_AddMainMenuItem("Inventory", "Inventory Description", _, OnMainMenuInventoryClick, 4);

	RegConsoleCmd("sm_inventory", Command_OpenInventory);
	RegAdminCmd("store_itemtypes", Command_PrintItemTypes, ADMFLAG_RCON, "Prints registered item types");

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
}

/**
 * Load plugin config.
 */
void LoadConfig() 
{
	Handle kv = CreateKeyValues("root");
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/inventory.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	char menuCommands[255];
	KvGetString(kv, "inventory_commands", menuCommands, sizeof(menuCommands));
	ExplodeString(menuCommands, " ", g_menuCommands, sizeof(g_menuCommands), sizeof(g_menuCommands[]));

	g_hideEmptyCategories = view_as<bool>(KvGetNum(kv, "hide_empty_categories", 0));
		
	CloseHandle(kv);
}

public void OnMainMenuInventoryClick(int client, const char[] value)
{
	OpenInventory(client);
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
	
	for (int index = 0; index < sizeof(g_menuCommands); index++) 
	{
		if (StrEqual(g_menuCommands[index], text))
		{
			OpenInventory(client);
			
			if (text[0] == 0x2F)
				return Plugin_Handled;
			
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

public Action Command_OpenInventory(int client, int args)
{
	OpenInventory(client);
	return Plugin_Handled;
}

public Action Command_PrintItemTypes(int client, int args)
{
	for (int itemTypeIndex = 0, size = GetArraySize(g_itemTypes); itemTypeIndex < size; itemTypeIndex++)
	{
		Handle itemType = GetArrayCell(g_itemTypes, itemTypeIndex);
		
		ResetPack(itemType);
		Handle plugin = ReadPackCell(itemType);

		SetPackPosition(itemType, view_as<DataPackPos>(24));
		char typeName[32];
		ReadPackString(itemType, typeName, sizeof(typeName));

		ResetPack(itemType);

		char pluginName[32];
		GetPluginFilename(plugin, pluginName, sizeof(pluginName));

		ReplyToCommand(client, " \"%s\" - %s", typeName, pluginName);			
	}

	return Plugin_Handled;
}

/**
* Opens the inventory menu for a client.
*
* @param client			Client index.
*
* @noreturn
*/
void OpenInventory(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	if (!IsClientInGame(client))
		return;

	Store_GetCategories(GetCategoriesCallback, true, GetClientSerial(client));
}

Handle categories_menu[MAXPLAYERS+1];

public void GetCategoriesCallback(int[] ids, int count, any serial)
{	
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
	
	categories_menu[client] = CreateMenu(InventoryMenuSelectHandle);
	SetMenuTitle(categories_menu[client], "%T\n \n", "Inventory", client);
		
	for (int category = 0; category < count; category++)
	{
		char requiredPlugin[STORE_MAX_REQUIREPLUGIN_LENGTH];
		Store_GetCategoryPluginRequired(ids[category], requiredPlugin, sizeof(requiredPlugin));
		
		int typeIndex;
		if (!StrEqual(requiredPlugin, "") && !GetTrieValue(g_itemTypeNameIndex, requiredPlugin, typeIndex))
			continue;

		Handle pack = CreateDataPack();
		WritePackCell(pack, GetClientSerial(client));
		WritePackCell(pack, ids[category]);
		WritePackCell(pack, count - category - 1);
		
		Handle filter = CreateTrie();
		SetTrieValue(filter, "category_id", ids[category]);
		SetTrieValue(filter, "flags", GetUserFlagBits(client));

		Store_GetUserItems(filter, GetSteamAccountID(client), Store_GetClientLoadout(client), GetItemsForCategoryCallback, pack);
	}
}

public void GetItemsForCategoryCallback(int[] ids, bool[] equipped, int[] itemCount, int count, int loadoutId, any pack)
{
	ResetPack(pack);
	
	int serial = ReadPackCell(pack);
	int categoryId = ReadPackCell(pack);
	int left = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	int client = GetClientFromSerial(serial);
	
	if (client <= 0)
		return;

	if (g_hideEmptyCategories && count <= 0)
	{
		if (left == 0)
		{
			SetMenuExitBackButton(categories_menu[client], true);
			DisplayMenu(categories_menu[client], client, 0);
		}
		return;
	}

	char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetCategoryDisplayName(categoryId, displayName, sizeof(displayName));

	//Store_PrintToChatAll("%s %i %i %i", displayName, g_hideEmptyCategories, count, left);

	//char description[STORE_MAX_DESCRIPTION_LENGTH];
	//Store_GetCategoryDescription(categoryId, description, sizeof(description));

	//char itemText[sizeof(displayName) + 1 + sizeof(description)];
	//Format(itemText, sizeof(itemText), "%s\n%s", displayName, description);
	
	char itemValue[8];
	IntToString(categoryId, itemValue, sizeof(itemValue));
	
	AddMenuItem(categories_menu[client], itemValue, displayName);

	if (left == 0)
	{
		SetMenuExitBackButton(categories_menu[client], true);
		DisplayMenu(categories_menu[client], client, 0);
	}
}

public int InventoryMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char categoryIndex[64];
		
		if (GetMenuItem(menu, slot, categoryIndex, sizeof(categoryIndex)))
			OpenInventoryCategory(client, StringToInt(categoryIndex));
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

/**
* Opens the inventory menu for a client in a specific category.
*
* @param client			Client index.
* @param categoryId		The category that you want to open.
*
* @noreturn
*/
void OpenInventoryCategory(int client, int categoryId, int slot = 0)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientSerial(client));
	WritePackCell(pack, categoryId);
	WritePackCell(pack, slot);
	
	Handle filter = CreateTrie();
	SetTrieValue(filter, "category_id", categoryId);
	SetTrieValue(filter, "flags", GetUserFlagBits(client));

	Store_GetUserItems(filter, GetSteamAccountID(client), Store_GetClientLoadout(client), GetUserItemsCallback, pack);
}

public void GetUserItemsCallback(int[] ids, bool[] equipped, int[] itemCount, int count, int loadoutId, any pack)
{
	ResetPack(pack);
	
	int serial = ReadPackCell(pack);
	int categoryId = ReadPackCell(pack);
	int slot = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	if (count == 0)
	{
		Store_PrintToChat(client, "%t", "No items in this category");
		OpenInventory(client);
		
		return;
	}
	
	char categoryDisplayName[64];
	Store_GetCategoryDisplayName(categoryId, categoryDisplayName, sizeof(categoryDisplayName));
		
	Handle menu = CreateMenu(InventoryCategoryMenuSelectHandle);
	SetMenuTitle(menu, "%T - %s\n \n", "Inventory", client, categoryDisplayName);
	
	for (int item = 0; item < count; item++)
	{
		// TODO: Option to display descriptions	
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], displayName, sizeof(displayName));
		
		char text[4 + sizeof(displayName) + 6];
		
		if (equipped[item])
			strcopy(text, sizeof(text), "[E] ");
		
		Format(text, sizeof(text), "%s%s", text, displayName);
		
		if (itemCount[item] > 1)
			Format(text, sizeof(text), "%s (%d)", text, itemCount[item]);
			
		char value[16];
		Format(value, sizeof(value), "%b,%d", equipped[item], ids[item]);
		
		AddMenuItem(menu, value, text);    
	}

	SetMenuExitBackButton(menu, true);
	
	if (slot == 0)
		DisplayMenu(menu, client, 0);   
	else
		DisplayMenuAtItem(menu, client, slot, 0);
}

public int InventoryCategoryMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char value[16];

		if (GetMenuItem(menu, slot, value, sizeof(value)))
		{
			char buffers[2][16];
			ExplodeString(value, ",", buffers, sizeof(buffers), sizeof(buffers[]));
			
			bool equipped = view_as<bool>(StringToInt(buffers[0]));
			int id = StringToInt(buffers[1]);
			
			char name[STORE_MAX_NAME_LENGTH];
			Store_GetItemName(id, name, sizeof(name));
			
			char type[STORE_MAX_TYPE_LENGTH];
			Store_GetItemType(id, type, sizeof(type));
			
			char loadoutSlot[STORE_MAX_LOADOUTSLOT_LENGTH];
			Store_GetItemLoadoutSlot(id, loadoutSlot, sizeof(loadoutSlot));
			
			int itemTypeIndex = -1;
			GetTrieValue(g_itemTypeNameIndex, type, itemTypeIndex);
			
			if (itemTypeIndex == -1)
			{
				Store_PrintToChat(client, "%t", "Item type not registered", type);
				Store_LogWarning("The item type '%s' wasn't registered by any plugin.", type);
				
				OpenInventoryCategory(client, Store_GetItemCategory(id));
				
				return 0;
			}
			
			Store_ItemUseAction callbackValue = Store_DoNothing;
			
			Handle itemType = GetArrayCell(g_itemTypes, itemTypeIndex);
			ResetPack(itemType);
			
			Handle plugin = ReadPackCell(itemType);
			Function callback = ReadPackFunction(itemType);
		
			Call_StartFunction(plugin, callback);
			Call_PushCell(client);
			Call_PushCell(id);
			Call_PushCell(equipped);
			Call_Finish(callbackValue);
			
			if (callbackValue != Store_DoNothing)
			{
				int auth = GetSteamAccountID(client);
					
				Handle pack = CreateDataPack();
				WritePackCell(pack, GetClientSerial(client));
				WritePackCell(pack, slot);

				if (callbackValue == Store_EquipItem)
				{
					if (StrEqual(loadoutSlot, ""))
					{
						Store_LogWarning("A user tried to equip an item that doesn't have a loadout slot.");
					}
					else
					{
						Store_SetItemEquippedState(auth, id, Store_GetClientLoadout(client), true, EquipItemCallback, pack);
					}
				}
				else if (callbackValue == Store_UnequipItem)
				{
					if (StrEqual(loadoutSlot, ""))
					{
						Store_LogWarning("A user tried to unequip an item that doesn't have a loadout slot.");
					}
					else
					{				
						Store_SetItemEquippedState(auth, id, Store_GetClientLoadout(client), false, EquipItemCallback, pack);
					}
				}
				else if (callbackValue == Store_DeleteItem)
				{
					Store_RemoveUserItem(auth, id, UseItemCallback, pack);
				}
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		OpenInventory(client);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

public void EquipItemCallback(int accountId, int itemId, int loadoutId, any pack)
{
	ResetPack(pack);
	
	int serial = ReadPackCell(pack);
	// new slot = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	OpenInventoryCategory(client, Store_GetItemCategory(itemId));
}

public void UseItemCallback(int accountId, int itemId, any pack)
{
	ResetPack(pack);
	
	int serial = ReadPackCell(pack);
	// new slot = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	OpenInventoryCategory(client, Store_GetItemCategory(itemId));
}

/**
* Registers an item type. 
*
* A type of an item defines its behaviour. Once you register a type, 
* the store will provide two callbacks for you:
* 	- Use callback: called when a player selects your item in his inventory.
*	- Attributes callback: called when the store loads the attributes of your item (optional).
*
* It is recommended that each plugin registers *one* item type. 
*
* @param type			Item type unique identifer - maximum 32 characters, no whitespaces, lower case only.
* @param plugin			The plugin owner of the callback(s).
* @param useCallback	Called when a player selects your item in his inventory.
* @param attrsCallback	Called when the store loads the attributes of your item.
*
* @noreturn
*/
void RegisterItemType(const char[] type, Handle plugin, Function useCallback, Function attrsCallback = INVALID_FUNCTION)
{
	if (g_itemTypes == null)
		g_itemTypes = CreateArray();
	
	if (g_itemTypeNameIndex == null)
	{
		g_itemTypeNameIndex = CreateTrie();
	}
	else
	{
		int itemType;
		if (GetTrieValue(g_itemTypeNameIndex, type, itemType))
		{
			CloseHandle(GetArrayCell(g_itemTypes, itemType));
		}
	}

	Handle itemType = CreateDataPack();
	WritePackCell(itemType, plugin); // 0
	WritePackFunction(itemType, useCallback); // 8
	WritePackFunction(itemType, attrsCallback); // 16
	WritePackString(itemType, type); // 24

	int index = PushArrayCell(g_itemTypes, itemType);
	SetTrieValue(g_itemTypeNameIndex, type, index);
}

public void Native_OpenInventory(Handle plugin, int params)
{       
	OpenInventory(GetNativeCell(1));
}

public void Native_OpenInventoryCategory(Handle plugin, int params)
{       
	OpenInventoryCategory(GetNativeCell(1), GetNativeCell(2));
}

public void Native_RegisterItemType(Handle plugin, int params)
{
	char type[STORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));
	
	RegisterItemType(type, plugin, GetNativeFunction(2), GetNativeFunction(3));
}

public int Native_IsItemTypeRegistered(Handle plugin, int params)
{
	char type[STORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));
	
	int typeIndex;
	return GetTrieValue(g_itemTypeNameIndex, type, typeIndex);
}

public int Native_CallItemAttrsCallback(Handle plugin, int params)
{
	if (g_itemTypeNameIndex == null)
		return false;
		
	char type[STORE_MAX_TYPE_LENGTH];
	GetNativeString(1, type, sizeof(type));

	int typeIndex;
	if (!GetTrieValue(g_itemTypeNameIndex, type, typeIndex))
		return false;

	char name[STORE_MAX_NAME_LENGTH];
	GetNativeString(2, name, sizeof(name));

	char attrs[STORE_MAX_ATTRIBUTES_LENGTH];
	GetNativeString(3, attrs, sizeof(attrs));		

	Handle pack = GetArrayCell(g_itemTypes, typeIndex);
	ResetPack(pack);

	Handle callbackPlugin = ReadPackCell(pack);
	
	SetPackPosition(pack, view_as<DataPackPos>(16));

	Function callback = ReadPackFunction(pack);

	if (callback == INVALID_FUNCTION)
		return false;

	Call_StartFunction(callbackPlugin, callback);
	Call_PushString(name);
	Call_PushString(attrs);
	Call_Finish();	
	
	return true;
}
