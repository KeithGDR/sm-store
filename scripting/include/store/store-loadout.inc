#if defined _store_loadout_included
  #endinput
#endif
#define _store_loadout_included

forward void Store_OnClientLoadoutChanged(int client);

/**
 * Opens the loadout menu for a client.
 *
 * @param client			Client index.
 *
 * @noreturn
 */
native void Store_OpenLoadoutMenu(int client);

/**
 * Gets client current loadout.
 *
 * @param client			Client index.
 *
 * @return Loadout index.
 */
native int Store_GetClientLoadout(int client);

public SharedPlugin __pl_loadout_store =
{
    name = "store-loadout",
    file = "store-loadout.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if defined REQUIRE_PLUGIN
public void __pl_store_loadout_SetNTVOptional()
{
	MarkNativeAsOptional("Store_OpenLoadoutMenu");  
	MarkNativeAsOptional("Store_GetClientLoadout");  
}
#endif