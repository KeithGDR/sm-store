#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <store>

char g_currencyName[64];
char g_menuCommands[32][32];

float g_refundPricePercentage;
bool g_confirmItemRefund = true;

public Plugin myinfo =
{
	name        = "[Store] Refund",
	author      = "alongub",
	description = "Refund component for [Store]",
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

	Store_AddMainMenuItem("Refund", "Refund Description", _, OnMainMenuRefundClick, 6);
	
	RegConsoleCmd("sm_refund", Command_OpenRefund);

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
}

/**
 * Configs just finished getting executed.
 */
public void OnConfigsExecuted()
{    
	Store_GetCurrencyName(g_currencyName, sizeof(g_currencyName));
}

/**
 * Load plugin config.
 */
void LoadConfig() 
{
	Handle kv = CreateKeyValues("root");
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/store/refund.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	char menuCommands[255];
	KvGetString(kv, "refund_commands", menuCommands, sizeof(menuCommands));
	ExplodeString(menuCommands, " ", g_menuCommands, sizeof(g_menuCommands), sizeof(g_menuCommands[]));
	
	g_refundPricePercentage = KvGetFloat(kv, "refund_price_percentage", 0.5);
	g_confirmItemRefund = view_as<bool>(KvGetNum(kv, "confirm_item_refund", 1));

	CloseHandle(kv);
}

public void OnMainMenuRefundClick(int client, const char[] value)
{
	OpenRefundMenu(client);
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
			OpenRefundMenu(client);
			
			if (text[0] == 0x2F)
				return Plugin_Handled;
			
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

public Action Command_OpenRefund(int client, int args)
{
	OpenRefundMenu(client);
	return Plugin_Handled;
}

/**
 * Opens the refund menu for a client.
 *
 * @param client			Client index.
 *
 * @noreturn
 */
void OpenRefundMenu(int client)
{
	Store_GetCategories(GetCategoriesCallback, true, GetClientSerial(client));
}

public void GetCategoriesCallback(int[] ids, int count, any serial)
{		
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	Handle menu = CreateMenu(RefundMenuSelectHandle);
	SetMenuTitle(menu, "%T\n \n", "Refund", client);
	
	for (int category = 0; category < count; category++)
	{
		char requiredPlugin[STORE_MAX_REQUIREPLUGIN_LENGTH];
		Store_GetCategoryPluginRequired(ids[category], requiredPlugin, sizeof(requiredPlugin));
		
		if (!StrEqual(requiredPlugin, "") && !Store_IsItemTypeRegistered(requiredPlugin))
			continue;
			
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetCategoryDisplayName(ids[category], displayName, sizeof(displayName));

		char description[STORE_MAX_DESCRIPTION_LENGTH];
		Store_GetCategoryDescription(ids[category], description, sizeof(description));

		char itemText[sizeof(displayName) + 1 + sizeof(description)];
		Format(itemText, sizeof(itemText), "%s\n%s", displayName, description);
		
		char itemValue[8];
		IntToString(ids[category], itemValue, sizeof(itemValue));
		
		AddMenuItem(menu, itemValue, itemText);
	}
	
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int RefundMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char categoryIndex[64];
		
		if (GetMenuItem(menu, slot, categoryIndex, sizeof(categoryIndex)))
			OpenRefundCategory(client, StringToInt(categoryIndex));
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
 * Opens the refund menu for a client in a specific category.
 *
 * @param client			Client index.
 * @param categoryId		The category that you want to open.
 *
 * @noreturn
 */
void OpenRefundCategory(int client, int categoryId, int slot = 0)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientSerial(client));
	WritePackCell(pack, categoryId);
	WritePackCell(pack, slot);

	Handle filter = CreateTrie();
	SetTrieValue(filter, "is_refundable", 1);
	SetTrieValue(filter, "category_id", categoryId);

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
		PrintToChat(client, "%s%t", STORE_PREFIX, "No items in this category");
		OpenRefundMenu(client);
		
		return;
	}
	
	char categoryDisplayName[64];
	Store_GetCategoryDisplayName(categoryId, categoryDisplayName, sizeof(categoryDisplayName));
		
	Handle menu = CreateMenu(RefundCategoryMenuSelectHandle);
	SetMenuTitle(menu, "%T - %s\n \n", "Refund", client, categoryDisplayName);
	
	for (int item = 0; item < count; item++)
	{
		// TODO: Option to display descriptions	
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], displayName, sizeof(displayName));
		
		char text[4 + sizeof(displayName) + 6];
		Format(text, sizeof(text), "%s%s", text, displayName);
		
		if (itemCount[item] > 1)
			Format(text, sizeof(text), "%s (%d)", text, itemCount[item]);
		
		Format(text, sizeof(text), "%s - %d %s", text, RoundToZero(Store_GetItemPrice(ids[item]) * g_refundPricePercentage), g_currencyName);

		char value[8];
		IntToString(ids[item], value, sizeof(value));
		
		AddMenuItem(menu, value, text);    
	}

	SetMenuExitBackButton(menu, true);
	
	if (slot == 0)
		DisplayMenu(menu, client, 0);   
	else
		DisplayMenuAtItem(menu, client, slot, 0); 
}

public int RefundCategoryMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char itemId[12];
		if (GetMenuItem(menu, slot, itemId, sizeof(itemId)))
		{
			if (g_confirmItemRefund)
			{
				DisplayConfirmationMenu(client, StringToInt(itemId));
			}
			else
			{			
				Store_RemoveUserItem(GetSteamAccountID(client), StringToInt(itemId), OnRemoveUserItemComplete, GetClientSerial(client));
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		OpenRefundMenu(client);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

void DisplayConfirmationMenu(int client, int itemId)
{
	char displayName[64];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));

	Handle menu = CreateMenu(ConfirmationMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Item Refund Confirmation", client, displayName, RoundToZero(Store_GetItemPrice(itemId) * g_refundPricePercentage), g_currencyName);

	char value[8];
	IntToString(itemId, value, sizeof(value));

	AddMenuItem(menu, value, "Yes");
	AddMenuItem(menu, "no", "No");

	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, 0);  
}

public int ConfirmationMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char itemId[12];
		if (GetMenuItem(menu, slot, itemId, sizeof(itemId)))
		{
			if (StrEqual(itemId, "no"))
			{
				OpenRefundMenu(client);
			}
			else
			{
				Store_RemoveUserItem(GetSteamAccountID(client), StringToInt(itemId), OnRemoveUserItemComplete, GetClientSerial(client));
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		OpenRefundMenu(client);
	}
	else if (action == MenuAction_DisplayItem) 
	{
		char display[64];
		GetMenuItem(menu, slot, "", 0, _, display, sizeof(display));

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", display, client);

		return RedrawMenuItem(buffer);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return false;
}

public void OnRemoveUserItemComplete(int accountId, int itemId, any serial)
{
	int client = GetClientFromSerial(serial);

	if (client == 0)
		return;

	int credits = RoundToZero(Store_GetItemPrice(itemId) * g_refundPricePercentage);

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientSerial(client));
	WritePackCell(pack, credits);
	WritePackCell(pack, itemId);

	Store_GiveCredits(accountId, credits, OnGiveCreditsComplete, pack);
}

public void OnGiveCreditsComplete(int accountId, any pack)
{
	ResetPack(pack);

	int serial = ReadPackCell(pack);
	int credits = ReadPackCell(pack);
	int itemId = ReadPackCell(pack);

	CloseHandle(pack);

	int client = GetClientFromSerial(serial);
	if (client == 0)
		return;

	char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
		
	PrintToChat(client, "%s%t", STORE_PREFIX, "Refund Message", displayName, credits, g_currencyName);

	OpenRefundMenu(client);
}