#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <store>

#define MAX_FILTERS 128

enum struct Filter
{
	char FilterMap[128];
	int FilterPlayerCount;
	int FilterFlags;
	float FilterMultiplier;
	float FilterMinimumMultiplier;
	float FilterMaximumMultiplier;
	int FilterAddend;
	int FilterMinimumAddend;
	int FilterMaximumAddend;
	int FilterTeam;
}

char g_currencyName[64];

float g_timeInSeconds;
bool g_enableMessagePerTick;

int g_baseMinimum;
int g_baseMaximum;

Filter g_filters[MAX_FILTERS];
int g_filterCount;

public Plugin myinfo =
{
	name        = "[Store] Distributor",
	author      = "Alongub, KeithGDR",
	description = "Distributor component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart() 
{
	LoadConfig();
	LoadTranslations("store.phrases");

	CreateTimer(g_timeInSeconds, ForgivePoints, _, TIMER_REPEAT);
}

/**
 * Configs just finished getting executed.
 */
public void OnAllPluginsLoaded()
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
	BuildPath(Path_SM, path, sizeof(path), "configs/store/distributor.cfg");
	
	if (!FileToKeyValues(kv, path)) 
	{
		CloseHandle(kv);
		SetFailState("Can't read config file %s", path);
	}

	g_timeInSeconds = KvGetFloat(kv, "time_per_distribute", 180.0);
	g_enableMessagePerTick = view_as<bool>(KvGetNum(kv, "enable_message_per_distribute", 0));

	if (KvJumpToKey(kv, "distribution"))
	{
		g_baseMinimum = KvGetNum(kv, "base_minimum", 1);
		g_baseMaximum = KvGetNum(kv, "base_maximum", 3);

		if (KvJumpToKey(kv, "filters"))
		{
			g_filterCount = 0;

			if (KvGotoFirstSubKey(kv))
			{
				do
				{
					g_filters[g_filterCount].FilterMultiplier = KvGetFloat(kv, "multiplier", 1.0);
					g_filters[g_filterCount].FilterMinimumMultiplier = KvGetFloat(kv, "min_multiplier", 1.0);
					g_filters[g_filterCount].FilterMaximumMultiplier = KvGetFloat(kv, "max_multiplier", 1.0);

					g_filters[g_filterCount].FilterAddend = KvGetNum(kv, "addend");
					g_filters[g_filterCount].FilterMinimumAddend = KvGetNum(kv, "min_addend");
					g_filters[g_filterCount].FilterMaximumAddend = KvGetNum(kv, "max_addend");

					g_filters[g_filterCount].FilterPlayerCount = KvGetNum(kv, "player_count", 0);
					g_filters[g_filterCount].FilterTeam = KvGetNum(kv, "team", -1);
                                       
					char flags[32];
					KvGetString(kv, "flags", flags, sizeof(flags));

					if (!StrEqual(flags, ""))
						g_filters[g_filterCount].FilterFlags = ReadFlagString(flags);

					KvGetString(kv, "map", g_filters[g_filterCount].FilterMap, 32);

					g_filterCount++;
				} while (KvGotoNextKey(kv));
			}
		}
	}

	CloseHandle(kv);
}


public Action ForgivePoints(Handle timer)
{
	char map[128];
	GetCurrentMap(map, sizeof(map));

	int clientCount = GetClientCount();

	int[] accountIds = new int[MaxClients];
	int[] credits = new int[MaxClients];

	int count = 0;
	
	for (int client = 1; client <= MaxClients; client++) 
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !IsClientObserver(client))
		{
			accountIds[count] = GetSteamAccountID(client);
			credits[count] = Calculate(client, map, clientCount);

			if (g_enableMessagePerTick)
			{
				PrintToChat(client, "%s%t", STORE_PREFIX, "Received Credits", credits[count], g_currencyName);
			}

			count++;
		}
	}

	Store_GiveDifferentCreditsToUsers(accountIds, count, credits);
	return Plugin_Continue;
}

int Calculate(int client, const char[] map, int clientCount)
{
	int min = g_baseMinimum;
	int max = g_baseMaximum;

	for (int filter = 0; filter < g_filterCount; filter++)
	{
		if ((g_filters[filter].FilterPlayerCount == 0 || clientCount >= g_filters[filter].FilterPlayerCount) && 
			(StrEqual(g_filters[filter].FilterMap, "") || StrEqual(g_filters[filter].FilterMap, map)) && 
			(g_filters[filter].FilterFlags == 0 || HasPermission(client, g_filters[filter].FilterFlags)) &&
			(g_filters[filter].FilterTeam == -1 || g_filters[filter].FilterTeam == GetClientTeam(client)))
		{
			min = RoundToZero(min * g_filters[filter].FilterMultiplier * g_filters[filter].FilterMinimumMultiplier) 
					+ g_filters[filter].FilterAddend + g_filters[filter].FilterMinimumAddend;

			max = RoundToZero(max * g_filters[filter].FilterMultiplier * g_filters[filter].FilterMaximumMultiplier)
					+ g_filters[filter].FilterAddend + g_filters[filter].FilterMaximumAddend;
		}
	}

	return GetRandomInt(min, max);
}

bool HasPermission(int client, int flags)
{
	AdminId admin = GetUserAdmin(client);
	if (admin == INVALID_ADMIN_ID)
		return false;

	int count = 0, found = 0;
	for (int i = 0; i <= 20; i++)
    {
		if (flags & (1<<i))
		{
			count++;

			if (GetAdminFlag(admin, view_as<AdminFlag>(i)))
				found++;
		}
	}

	if (count == found)
		return true;

	return false;
}