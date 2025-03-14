#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <adminmenu>
#include <colorlib>
#include <store>
#include <smartdm>

#define MAX_CREDIT_CHOICES 100

enum struct Present
{
	int Present_Owner;
	char Present_Data[64];
}

enum GiftAction
{
	GiftAction_Send,
	GiftAction_Drop
}

enum GiftType
{
	GiftType_Credits,
	GiftType_Item
}

enum struct GiftRequest
{
	bool GiftRequestActive;
	int GiftRequestSender;
	GiftType GiftRequestType;
	int GiftRequestValue;
}

char g_currencyName[64];
char g_menuCommands[32][32];

int g_creditChoices[MAX_CREDIT_CHOICES];
GiftRequest g_giftRequests[MAXPLAYERS+1];

Present g_spawnedPresents[2048];
char g_itemModel[32];
char g_creditsModel[32];
bool g_drop_enabled;

char g_game[32];

public Plugin myinfo =
{
	name        = "[Store] Gifting",
	author      = "Alongub, KeithGDR",
	description = "Gifting component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
	GetGameFolderName(g_game, sizeof(g_game));
	LoadConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("store.phrases");

	Store_AddMainMenuItem("Gift", "Gift Description", _, OnMainMenuGiftClick, 5);
	
	RegConsoleCmd("sm_gift", Command_OpenGifting);
	RegConsoleCmd("sm_accept", Command_Accept);

	if (g_drop_enabled)
	{
		RegConsoleCmd("sm_drop", Command_Drop);
	}

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");

	HookEvent("player_disconnect", Event_PlayerDisconnect);
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
	BuildPath(Path_SM, path, sizeof(path), "configs/store/gifting.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	char menuCommands[255];
	KvGetString(kv, "gifting_commands", menuCommands, sizeof(menuCommands));
	ExplodeString(menuCommands, " ", g_menuCommands, sizeof(g_menuCommands), sizeof(g_menuCommands[]));
	
	char creditChoices[MAX_CREDIT_CHOICES][10];

	char creditChoicesString[255];
	KvGetString(kv, "credits_choices", creditChoicesString, sizeof(creditChoicesString));

	int choices = ExplodeString(creditChoicesString, " ", creditChoices, sizeof(creditChoices), sizeof(creditChoices[]));
	for (int choice = 0; choice < choices; choice++)
		g_creditChoices[choice] = StringToInt(creditChoices[choice]);

	g_drop_enabled = view_as<bool>(KvGetNum(kv, "drop_enabled", 0));

	if (g_drop_enabled)
	{
		KvGetString(kv, "itemModel", g_itemModel, sizeof(g_itemModel), "");
		KvGetString(kv, "creditsModel", g_creditsModel, sizeof(g_creditsModel), "");

		if (!g_itemModel[0] || !FileExists(g_itemModel, true))
		{
			if(StrEqual(g_game, "cstrike"))
			{
				strcopy(g_itemModel,sizeof(g_itemModel), "models/items/cs_gift.mdl");
			}
			else if (StrEqual(g_game, "tf"))
			{
				strcopy(g_itemModel,sizeof(g_itemModel), "models/items/tf_gift.mdl");
			}
			else if (StrEqual(g_game, "dod"))
			{
				strcopy(g_itemModel,sizeof(g_itemModel), "models/items/dod_gift.mdl");
			}
			else
				g_drop_enabled = false;
		}
		
		if (g_drop_enabled && (!g_creditsModel[0] || !FileExists(g_creditsModel, true))) 
		{
			// if the credits model can't be found, use the item model
			strcopy(g_creditsModel,sizeof(g_creditsModel),g_itemModel);
		}
	}

	CloseHandle(kv);
}

public void OnMapStart()
{
	if(g_drop_enabled) // false if the files are not found
	{
		PrecacheModel(g_itemModel, true);
		Downloader_AddFileToDownloadsTable(g_itemModel);

		if (!StrEqual(g_itemModel, g_creditsModel))
		{
			PrecacheModel(g_creditsModel, true);
			Downloader_AddFileToDownloadsTable(g_creditsModel);
		}
	}
}

public Action Command_Drop(int client, int args)
{
	if (args==0)
	{
		ReplyToCommand(client, "%sUsage: sm_drop <%s>", STORE_PREFIX, g_currencyName);
		{
			return Plugin_Handled;
		}
	}

	char sCredits[10];
	GetCmdArg(1, sCredits, sizeof(sCredits));

	int credits = StringToInt(sCredits);

	if (credits < 1)
	{
		ReplyToCommand(client, "%s%d is not a valid amount!", STORE_PREFIX, credits);
		{
			return Plugin_Handled;
		}
	}

	Handle pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, credits);

	Store_GetCredits(GetSteamAccountID(client), DropGetCreditsCallback, pack);
	return Plugin_Handled;
}

public void DropGetCreditsCallback(int credits, any pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int needed = ReadPackCell(pack);

	if (credits >= needed)
	{
		Store_GiveCredits(GetSteamAccountID(client), -needed, DropGiveCreditsCallback, pack);
	}
	else
	{
		Store_PrintToChat(client, "%t", "Not enough credits", g_currencyName);
	}
}

public void DropGiveCreditsCallback(int accountId, any pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int credits = ReadPackCell(pack);
	CloseHandle(pack);

	char value[32];
	Format(value, sizeof(value), "credits,%d", credits);

	Store_PrintToChat(client, "%t", "Gift Credits Dropped", credits, g_currencyName);

	int present;
	if((present = SpawnPresent(client, g_creditsModel)) != -1)
	{
		strcopy(g_spawnedPresents[present].Present_Data, 64, value);
		g_spawnedPresents[present].Present_Owner = client;
	}
}

public void OnMainMenuGiftClick(int client, const char[] value)
{
	OpenGiftingMenu(client);
}

public Action Event_PlayerDisconnect(Handle event, const char[] name, bool dontBroadcast) 
{ 
	g_giftRequests[GetClientOfUserId(GetEventInt(event, "userid"))].GiftRequestActive = false;
	return Plugin_Continue;
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
			OpenGiftingMenu(client);
			
			if (text[0] == 0x2F)
				return Plugin_Handled;
			
			return Plugin_Continue;
		}
	}
	
	return Plugin_Continue;
}

public Action Command_OpenGifting(int client, int args)
{
	OpenGiftingMenu(client);
	return Plugin_Handled;
}

/**
 * Opens the gifting menu for a client.
 *
 * @param client			Client index.
 *
 * @noreturn
 */
void OpenGiftingMenu(int client)
{
	Handle menu = CreateMenu(GiftTypeMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Gift Type Menu Title", client);

	char item[32];
	Format(item, sizeof(item), "%T", "Item", client);

	AddMenuItem(menu, "credits", g_currencyName);
	AddMenuItem(menu, "item", item);

	DisplayMenu(menu, client, 0);
}

public int GiftTypeMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char giftType[10];
		
		if (GetMenuItem(menu, slot, giftType, sizeof(giftType)))
		{
			if (StrEqual(giftType, "credits"))
			{
				if (g_drop_enabled)
				{
					OpenChooseActionMenu(client, GiftType_Credits);
				}
				else
				{
					OpenChoosePlayerMenu(client, GiftType_Credits);
				}
			}
			else if (StrEqual(giftType, "item"))
			{
				if (g_drop_enabled)
				{
					OpenChooseActionMenu(client, GiftType_Item);
				}
				else
				{
					OpenChoosePlayerMenu(client, GiftType_Item);
				}
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_Exit)
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

void OpenChooseActionMenu(int client, GiftType giftType)
{
	Handle menu = CreateMenu(ChooseActionMenuSelectHandle);
	SetMenuTitle(menu, "%T", "Gift Delivery Method", client);

	char s_giftType[32];
	if (giftType == GiftType_Credits)
		strcopy(s_giftType, sizeof(s_giftType), "credits");
	else if (giftType == GiftType_Item)
		strcopy(s_giftType, sizeof(s_giftType), "item");

	char send[32], drop[32];
	Format(send, sizeof(send), "%s,send", s_giftType);
	Format(drop, sizeof(drop), "%s,drop", s_giftType);

	char methodSend[32], methodDrop[32];
	Format(methodSend, sizeof(methodSend), "%T", "Gift Method Send", client);
	Format(methodDrop, sizeof(methodDrop), "%T", "Gift Method Drop", client);

	AddMenuItem(menu, send, methodSend);
	AddMenuItem(menu, drop, methodDrop);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int ChooseActionMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char values[32];
			if (GetMenuItem(menu, slot, values, sizeof(values)))
			{
				char brokenValues[2][32];
				ExplodeString(values, ",", brokenValues, sizeof(brokenValues), sizeof(brokenValues[]));

				GiftType giftType;

				if (StrEqual(brokenValues[0], "credits"))
				{
					giftType = GiftType_Credits;
				}
				else if (StrEqual(brokenValues[0], "item"))
				{
					giftType = GiftType_Item;
				}

				if (StrEqual(brokenValues[1], "send"))
				{
					OpenChoosePlayerMenu(client, giftType);
				}
				else if (StrEqual(brokenValues[1], "drop"))
				{
					if (giftType == GiftType_Item)
					{
						OpenSelectItemMenu(client, GiftAction_Drop, -1);
					}
					else if (giftType == GiftType_Credits)
					{
						OpenSelectCreditsMenu(client, GiftAction_Drop, -1);
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			if (slot == MenuCancel_ExitBack)
			{
				OpenGiftingMenu(client);
			}
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}

	return 0;
}

void OpenChoosePlayerMenu(int client, GiftType giftType)
{
	Handle menu;

	if (giftType == GiftType_Credits)
		menu = CreateMenu(ChoosePlayerCreditsMenuSelectHandle);
	else if (giftType == GiftType_Item)
		menu = CreateMenu(ChoosePlayerItemMenuSelectHandle);
	else
		return;

	SetMenuTitle(menu, "Select Player:\n \n");

	AddTargetsToMenu2(menu, 0, COMMAND_FILTER_NO_BOTS);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);	
}

public int ChoosePlayerCreditsMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char userid[10];
		if (GetMenuItem(menu, slot, userid, sizeof(userid)))
			OpenSelectCreditsMenu(client, GiftAction_Send, GetClientOfUserId(StringToInt(userid)));
	}
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_ExitBack)
		{
			OpenGiftingMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

public int ChoosePlayerItemMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char userid[10];
		if (GetMenuItem(menu, slot, userid, sizeof(userid)))
			OpenSelectItemMenu(client, GiftAction_Send, GetClientOfUserId(StringToInt(userid)));
	}
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_ExitBack)
		{
			OpenGiftingMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

void OpenSelectCreditsMenu(int client, GiftAction giftAction, int giftTo = -1)
{
	if (giftAction == GiftAction_Send && giftTo == -1)
		return;

	Handle menu = CreateMenu(CreditsMenuSelectItem);

	SetMenuTitle(menu, "Select %s:", g_currencyName);

	for (int choice = 0; choice < sizeof(g_creditChoices); choice++)
	{
		if (g_creditChoices[choice] == 0)
			continue;

		char text[48];
		IntToString(g_creditChoices[choice], text, sizeof(text));

		char value[32];
		Format(value, sizeof(value), "%d,%d,%d", giftAction, giftTo, g_creditChoices[choice]);

		AddMenuItem(menu, value, text);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int CreditsMenuSelectItem(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char value[32];
		if (GetMenuItem(menu, slot, value, sizeof(value)))
		{
			char values[3][16];
			ExplodeString(value, ",", values, sizeof(values), sizeof(values[]));

			GiftAction giftAction = view_as<GiftAction>(StringToInt(values[0]));
			int giftTo = StringToInt(values[1]);
			int credits = StringToInt(values[2]);

			Handle pack = CreateDataPack();
			WritePackCell(pack, client);
			WritePackCell(pack, giftAction);
			WritePackCell(pack, giftTo);
			WritePackCell(pack, credits);

			Store_GetCredits(GetSteamAccountID(client), GetCreditsCallback, pack);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_ExitBack)
		{
			OpenGiftingMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

public void GetCreditsCallback(int credits, any pack)
{
	ResetPack(pack);

	int client = ReadPackCell(pack);
	GiftAction giftAction = ReadPackCell(pack);
	int giftTo = ReadPackCell(pack);
	int giftCredits = ReadPackCell(pack);

	CloseHandle(pack);

	if (giftCredits > credits)
	{
		Store_PrintToChat(client, "%t", "Not enough credits", g_currencyName);
	}
	else
	{
		OpenGiveCreditsConfirmMenu(client, giftAction, giftTo, giftCredits);
	}
}

void OpenGiveCreditsConfirmMenu(int client, GiftAction giftAction, int giftTo, int credits)
{
	Handle menu = CreateMenu(CreditsConfirmMenuSelectItem);
	char value[32];

	if (giftAction == GiftAction_Send)
	{
		char name[32];
		GetClientName(giftTo, name, sizeof(name));
		SetMenuTitle(menu, "%T", "Gift Credit Confirmation", client, name, credits, g_currencyName);
		Format(value, sizeof(value), "%d,%d,%d", giftAction, giftTo, credits);
	}
	else if (giftAction == GiftAction_Drop)
	{
		SetMenuTitle(menu, "%T", "Drop Credit Confirmation", client, credits, g_currencyName);
		Format(value, sizeof(value), "%d,%d,%d", giftAction, giftTo, credits);
	}

	AddMenuItem(menu, value, "Yes");
	AddMenuItem(menu, "", "No");

	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, 0);  
}

public int CreditsConfirmMenuSelectItem(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char value[32];
		if (GetMenuItem(menu, slot, value, sizeof(value)))
		{
			if (!StrEqual(value, ""))
			{
				char values[3][16];
				ExplodeString(value, ",", values, sizeof(values), sizeof(values[]));

				GiftAction giftAction = view_as<GiftAction>(StringToInt(values[0]));
				int giftTo = StringToInt(values[1]);
				int credits = StringToInt(values[2]);

				if (giftAction == GiftAction_Send)
				{
					AskForPermission(client, giftTo, GiftType_Credits, credits);
				}
				else if (giftAction == GiftAction_Drop)
				{
					char data[32];
					Format(data, sizeof(data), "credits,%d", credits);

					Handle pack = CreateDataPack();
					WritePackCell(pack, client);
					WritePackCell(pack, credits);

					Store_GetCredits(GetSteamAccountID(client), DropGetCreditsCallback, pack);
				}
			}
		}
	}
	else if (action == MenuAction_DisplayItem) 
	{
		char display[64];
		GetMenuItem(menu, slot, "", 0, _, display, sizeof(display));

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", display, client);

		return RedrawMenuItem(buffer);
	}	
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_ExitBack)
		{
			OpenChoosePlayerMenu(client, GiftType_Credits);
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return false;
}

void OpenSelectItemMenu(int client, GiftAction giftAction, int giftTo = -1)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientSerial(client));
	WritePackCell(pack, giftAction);
	WritePackCell(pack, giftTo);

	Handle filter = CreateTrie();
	SetTrieValue(filter, "is_tradeable", 1);

	Store_GetUserItems(filter, GetSteamAccountID(client), Store_GetClientLoadout(client), GetUserItemsCallback, pack);
}

public void GetUserItemsCallback(int[] ids, bool[] equipped, int[] itemCount, int count, int loadoutId, any pack)
{		
	ResetPack(pack);
	
	int serial = ReadPackCell(pack);
	GiftAction giftAction = ReadPackCell(pack);
	int giftTo = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	int client = GetClientFromSerial(serial);
	
	if (client == 0)
		return;
		
	if (count == 0)
	{
		Store_PrintToChat(client, "%t", "No items");	
		return;
	}
	
	Handle menu = CreateMenu(ItemMenuSelectHandle);
	SetMenuTitle(menu, "Select item:\n \n");
	
	for (int item = 0; item < count; item++)
	{
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(ids[item], displayName, sizeof(displayName));
		
		char text[4 + sizeof(displayName) + 6];
		Format(text, sizeof(text), "%s%s", text, displayName);
		
		if (itemCount[item] > 1)
			Format(text, sizeof(text), "%s (%d)", text, itemCount[item]);
		
		char value[32];
		Format(value, sizeof(value), "%d,%d,%d", giftAction, giftTo, ids[item]);
		
		AddMenuItem(menu, value, text);    
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int ItemMenuSelectHandle(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char value[32];
		if (GetMenuItem(menu, slot, value, sizeof(value)))
		{
			OpenGiveItemConfirmMenu(client, value);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		OpenGiftingMenu(client); //OpenChoosePlayerMenu(client, GiftType_Item);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return 0;
}

void OpenGiveItemConfirmMenu(int client, const char[] value)
{
	char values[3][16];
	ExplodeString(value, ",", values, sizeof(values), sizeof(values[]));

	GiftAction giftAction = view_as<GiftAction>(StringToInt(values[0]));
	int giftTo = StringToInt(values[1]);
	int itemId = StringToInt(values[2]);

	char name[32];
	if (giftAction == GiftAction_Send)
	{
		GetClientName(giftTo, name, sizeof(name));
	}

	char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));

	Handle menu = CreateMenu(ItemConfirmMenuSelectItem);
	if (giftAction == GiftAction_Send)
		SetMenuTitle(menu, "%T", "Gift Item Confirmation", client, name, displayName);
	else if (giftAction == GiftAction_Drop)
		SetMenuTitle(menu, "%T", "Drop Item Confirmation", client, displayName);

	AddMenuItem(menu, value, "Yes");
	AddMenuItem(menu, "", "No");

	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, 0);
}

public int ItemConfirmMenuSelectItem(Handle menu, MenuAction action, int client, int slot)
{
	if (action == MenuAction_Select)
	{
		char value[32];
		if (GetMenuItem(menu, slot, value, sizeof(value)))
		{
			if (!StrEqual(value, ""))
			{
				char values[3][16];
				ExplodeString(value, ",", values, sizeof(values), sizeof(values[]));

				GiftAction giftAction = view_as<GiftAction>(StringToInt(values[0]));
				int giftTo = StringToInt(values[1]);
				int itemId = StringToInt(values[2]);

				if (giftAction == GiftAction_Send)
					AskForPermission(client, giftTo, GiftType_Item, itemId);
				else if (giftAction == GiftAction_Drop)
				{
					int present;
					if((present = SpawnPresent(client, g_itemModel)) != -1)
					{
						char data[32];
						Format(data, sizeof(data), "item,%d", itemId);

						strcopy(g_spawnedPresents[present].Present_Data, 64, data);
						g_spawnedPresents[present].Present_Owner = client;

						Store_RemoveUserItem(GetSteamAccountID(client), itemId, DropItemCallback, client);
					}
				}
			}
		}
	}
	else if (action == MenuAction_DisplayItem) 
	{
		char display[64];
		GetMenuItem(menu, slot, "", 0, _, display, sizeof(display));

		char buffer[255];
		Format(buffer, sizeof(buffer), "%T", display, client);

		return RedrawMenuItem(buffer);
	}	
	else if (action == MenuAction_Cancel)
	{
		if (slot == MenuCancel_ExitBack)
		{
			OpenGiftingMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	return false;
}

public void DropItemCallback(int accountId, int itemId, any client)
{
	char displayName[64];
	Store_GetItemDisplayName(itemId, displayName, sizeof(displayName));
	Store_PrintToChat(client, "%t", "Gift Item Dropped", displayName);
}

void AskForPermission(int client, int giftTo, GiftType giftType, int value)
{
	char giftToName[32];
	GetClientName(giftTo, giftToName, sizeof(giftToName));

	Store_PrintToChatEx(client, giftTo, "%T", "Gift Waiting to accept", client, giftToName);

	char clientName[32];
	GetClientName(client, clientName, sizeof(clientName));	

	char what[64];

	if (giftType == GiftType_Credits)
		Format(what, sizeof(what), "%d %s", value, g_currencyName);
	else if (giftType == GiftType_Item)
		Store_GetItemDisplayName(value, what, sizeof(what));	

	Store_PrintToChatEx(giftTo, client, "%T", "Gift Request Accept", client, clientName, what);

	g_giftRequests[giftTo].GiftRequestActive = true;
	g_giftRequests[giftTo].GiftRequestSender = client;
	g_giftRequests[giftTo].GiftRequestType = giftType;
	g_giftRequests[giftTo].GiftRequestValue = value;
}

public Action Command_Accept(int client, int args)
{
	if (!g_giftRequests[client].GiftRequestActive)
		return Plugin_Continue;

	if (g_giftRequests[client].GiftRequestType == GiftType_Credits)
		GiftCredits(g_giftRequests[client].GiftRequestSender, client, g_giftRequests[client].GiftRequestValue);
	else
		GiftItem(g_giftRequests[client].GiftRequestSender, client, g_giftRequests[client].GiftRequestValue);

	g_giftRequests[client].GiftRequestActive = false;
	return Plugin_Handled;
}

void GiftCredits(int from, int to, int amount)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, from); // 0
	WritePackCell(pack, to); // 8
	WritePackCell(pack, amount);

	Store_GiveCredits(GetSteamAccountID(from), -amount, TakeCreditsCallback, pack);
}

public void TakeCreditsCallback(int accountId, any pack)
{
	SetPackPosition(pack, view_as<DataPackPos>(8));

	int to = ReadPackCell(pack);
	int amount = ReadPackCell(pack);

	Store_GiveCredits(GetSteamAccountID(to), amount, GiveCreditsCallback, pack);
}

public void GiveCreditsCallback(int accountId, any pack)
{
	ResetPack(pack);

	int from = ReadPackCell(pack);
	int to = ReadPackCell(pack);

	CloseHandle(pack);

	char receiverName[32];
	GetClientName(to, receiverName, sizeof(receiverName));	

	Store_PrintToChatEx(from, to, "%t", "Gift accepted - sender", receiverName);

	char senderName[32];
	GetClientName(from, senderName, sizeof(senderName));

	Store_PrintToChatEx(to, from, "%t", "Gift accepted - receiver", senderName);
}

void GiftItem(int from, int to, int itemId)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, from); // 0
	WritePackCell(pack, to); // 8
	WritePackCell(pack, itemId);

	Store_RemoveUserItem(GetSteamAccountID(from), itemId, RemoveUserItemCallback, pack);
}

public void RemoveUserItemCallback(int accountId, int itemId, any pack)
{
	SetPackPosition(pack, view_as<DataPackPos>(8));

	int to = ReadPackCell(pack);

	Store_GiveItem(GetSteamAccountID(to), itemId, Store_Gift, GiveCreditsCallback, pack);
}

int SpawnPresent(int owner, const char[] model)
{
	int present;

	if((present = CreateEntityByName("prop_physics_override")) != -1)
	{
		char targetname[100];

		Format(targetname, sizeof(targetname), "gift_%i", present);

		DispatchKeyValue(present, "model", model);
		DispatchKeyValue(present, "physicsmode", "2");
		DispatchKeyValue(present, "massScale", "1.0");
		DispatchKeyValue(present, "targetname", targetname);
		DispatchSpawn(present);
		
		SetEntProp(present, Prop_Send, "m_usSolidFlags", 8);
		SetEntProp(present, Prop_Send, "m_CollisionGroup", 1);
		
		float pos[3];
		GetClientAbsOrigin(owner, pos);
		pos[2] += 16;

		TeleportEntity(present, pos, NULL_VECTOR, NULL_VECTOR);
		
		int rotator = CreateEntityByName("func_rotating");
		DispatchKeyValueVector(rotator, "origin", pos);
		DispatchKeyValue(rotator, "targetname", targetname);
		DispatchKeyValue(rotator, "maxspeed", "200");
		DispatchKeyValue(rotator, "friction", "0");
		DispatchKeyValue(rotator, "dmg", "0");
		DispatchKeyValue(rotator, "solid", "0");
		DispatchKeyValue(rotator, "spawnflags", "64");
		DispatchSpawn(rotator);
		
		SetVariantString("!activator");
		AcceptEntityInput(present, "SetParent", rotator, rotator);
		AcceptEntityInput(rotator, "Start");
		
		SetEntPropEnt(present, Prop_Send, "m_hEffectEntity", rotator);

		SDKHook(present, SDKHook_StartTouch, OnStartTouch);
	}

	return present;
}

public void OnStartTouch(int present, int client)
{
	if(!(0<client<=MaxClients))
		return;

	if(g_spawnedPresents[present].Present_Owner == client)
		return;

	int rotator = GetEntPropEnt(present, Prop_Send, "m_hEffectEntity");
	if(rotator && IsValidEdict(rotator))
		AcceptEntityInput(rotator, "Kill");

	AcceptEntityInput(present, "Kill");

	char values[2][16];
	ExplodeString(g_spawnedPresents[present].Present_Data, ",", values, sizeof(values), sizeof(values[]));

	Handle pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackString(pack,values[0]);

	if (StrEqual(values[0],"credits"))
	{
		int credits = StringToInt(values[1]);
		WritePackCell(pack, credits);
		Store_GiveCredits(GetSteamAccountID(client), credits, PickupGiveCallback, pack);
	}
	else if (StrEqual(values[0], "item"))
	{
		int itemId = StringToInt(values[1]);
		WritePackCell(pack, itemId);
		Store_GiveItem(GetSteamAccountID(client), itemId, Store_Gift, PickupGiveCallback, pack);
	}
}

public void PickupGiveCallback(int accountId, any pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	char itemType[32];
	ReadPackString(pack, itemType, sizeof(itemType));
	int value = ReadPackCell(pack);

	if (StrEqual(itemType, "credits"))
	{
		Store_PrintToChat(client, "%t", "Gift Credits Found", value, g_currencyName); //translate
	}
	else if (StrEqual(itemType, "item"))
	{
		char displayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(value, displayName, sizeof(displayName));
		Store_PrintToChat(client, "%t", "Gift Item Found", displayName); //translate
	}
}