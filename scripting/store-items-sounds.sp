#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <json>
#include <store>
#include <colorlib>
#include <soundlib>

#define MAX_SOUNDS 512

enum struct Sound
{
	char SoundName[STORE_MAX_NAME_LENGTH];
	char SoundPath[PLATFORM_MAX_PATH];
	float SoundVolume;
	char SoundText[192];
	float SoundLength;
}

Sound g_sounds[MAX_SOUNDS];
int g_soundCount;

Handle g_soundsNameIndex;

int g_lastSound = 0;
float g_lastSoundPlayedTime = 0.0;

Handle g_hGlobalWaitTimeCvar = null;
float g_waitTime = 2.0;

public Plugin myinfo =
{
	name        = "[Store] Sounds",
	author      = "Alongub, KeithGDR",
	description = "Sounds component for [Store]",
	version     = STORE_VERSION,
	url         = "https://github.com/KeithGDR/sm-store"
};

/**
 * Plugin is loading.
 */
public void OnPluginStart()
{
    LoadTranslations("store.phrases");
    LoadTranslations("store-sounds.phrases");

    Store_RegisterItemType("sound", OnSoundUse, OnSoundAttributesLoad);

    g_hGlobalWaitTimeCvar = CreateConVar("store_sounds_global_wait_time", "3.0", "Minimum time in seconds between each sound.");
    HookConVarChange(g_hGlobalWaitTimeCvar, Action_OnSettingsChange);

    AutoExecConfig(true, "store-sounds");

    g_waitTime = GetConVarFloat(g_hGlobalWaitTimeCvar);
}

/** 
 * Called when a new API library is loaded.
 */
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "store-inventory"))
	{
		Store_RegisterItemType("sound", OnSoundUse, OnSoundAttributesLoad);
	}	
}

/**
 * Map is starting.
 */
public void OnMapStart()
{
	g_lastSoundPlayedTime = 0.0;
	g_lastSound = 0;

	for (int item = 0; item < g_soundCount; item++)
	{
		char fullSoundPath[PLATFORM_MAX_PATH];
		Format(fullSoundPath, sizeof(fullSoundPath), "sound/%s", g_sounds[item].SoundPath);

		if (strcmp(fullSoundPath, "") != 0 && (FileExists(fullSoundPath) || FileExists(fullSoundPath, true)))
		{
		    PrecacheSound(g_sounds[item].SoundPath);
		    AddFileToDownloadsTable(fullSoundPath);
		}
	}
}

public void Action_OnSettingsChange(Handle cvar, const char[] oldvalue, const char[] newvalue)
{
	if (cvar == g_hGlobalWaitTimeCvar)
	{
		g_waitTime = StringToFloat(newvalue);
	}
}

public void Store_OnReloadItems() 
{
	if (g_soundsNameIndex != null)
		CloseHandle(g_soundsNameIndex);
		
	g_soundsNameIndex = CreateTrie();
	g_soundCount = 0;
}

public void OnSoundAttributesLoad(const char[] itemName, const char[] attrs)
{
	strcopy(g_sounds[g_soundCount].SoundName, STORE_MAX_NAME_LENGTH, itemName);
		
	SetTrieValue(g_soundsNameIndex, g_sounds[g_soundCount].SoundName, g_soundCount);
	
	JSON_Object json = json_decode(attrs);
	json.GetString("path", g_sounds[g_soundCount].SoundPath, PLATFORM_MAX_PATH);
	json.GetString("text", g_sounds[g_soundCount].SoundText, 192);

	g_sounds[g_soundCount].SoundVolume = json.GetFloat("volume");
	if (g_sounds[g_soundCount].SoundVolume == 0.0)
		g_sounds[g_soundCount].SoundVolume = 1.0;

	char fullSoundPath[PLATFORM_MAX_PATH];
	Format(fullSoundPath, sizeof(fullSoundPath), "sound/%s", g_sounds[g_soundCount].SoundPath);
	
	if (strcmp(fullSoundPath, "") != 0 && (FileExists(fullSoundPath) || FileExists(fullSoundPath, true)))
	{
	    PrecacheSound(g_sounds[g_soundCount].SoundPath);
	    AddFileToDownloadsTable(fullSoundPath);
	}

	Handle soundFile = OpenSoundFile(g_sounds[g_soundCount].SoundPath);
	
	if (soundFile != null) 
	{
		g_sounds[g_soundCount].SoundLength = GetSoundLengthFloat(soundFile);
		CloseHandle(soundFile); 
	}

	CloseHandle(json);
	g_soundCount++;
}

public Store_ItemUseAction OnSoundUse(int client, int itemId, bool equipped)
{
	if (!IsClientInGame(client))
	{
		return Store_DoNothing;
	}

	if (g_lastSoundPlayedTime != 0.0 && g_lastSound != 0 && GetGameTime() < g_lastSoundPlayedTime + g_sounds[g_lastSound].SoundLength + g_waitTime)
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "Wait until sound finishes");
		return Store_DoNothing;
	}

	char itemName[STORE_MAX_NAME_LENGTH];
	Store_GetItemName(itemId, itemName, sizeof(itemName));

	int sound = -1;
	if (!GetTrieValue(g_soundsNameIndex, itemName, sound))
	{
		PrintToChat(client, "%s%t", STORE_PREFIX, "No item attributes");
		return Store_DoNothing;
	}

	char playerName[32];
	GetClientName(client, playerName, sizeof(playerName));

	if (StrEqual(g_sounds[sound].SoundText, ""))
	{
		char soundDisplayName[STORE_MAX_DISPLAY_NAME_LENGTH];
		Store_GetItemDisplayName(itemId, soundDisplayName, sizeof(soundDisplayName));

		CPrintToChatAllEx(client, "%t", "Player has played a sound", playerName, soundDisplayName);
	}
	else
	{
		CPrintToChatAllEx(client, "{teamcolor}%s{default} %s!", playerName, g_sounds[sound].SoundText);
	}

	EmitSoundToAll(g_sounds[sound].SoundPath, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_sounds[sound].SoundVolume);

	g_lastSound = sound;
	g_lastSoundPlayedTime = GetGameTime();

	return Store_DeleteItem;
}