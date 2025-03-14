#if defined _store_core_included
#endinput
#endif
#define _store_core_included

typeset Store_MenuItemClickCallback {
	function void (int client, const char[] value);
}

/**
 * Opens the main menu for a player.
 *
 * @param client		Client Index
 *
 * @noreturn
 */
native void Store_OpenMainMenu(int client);

/**
 * Adds an item to the main menu. 
 *
 * @param displayName		The text of the item, as it is shown to the player.
 * @param description		A short description of the item.
 * @param value				Item information string that will be sent to the callback.
 * @param callback			Callback to the item click event.
 * @param order				Preferred position of the item in the menu.
 *
 * @noreturn
 */
native void Store_AddMainMenuItem(const char[] displayName, const char[] description = "", const char[] value = "", Store_MenuItemClickCallback callback, int order = 32);

/**
 * Retrieve currency name as it is defined in the core condig file.
 *
 * @param currencyName		Buffer to store the currency name in.
 * @param maxLength			Maximum length of string buffer.
 *
 * @noreturn
 */
native void Store_GetCurrencyName(char[] currencyName, int maxLength);

public SharedPlugin __pl_store =
{
	name = "store",
	file = "store-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if defined REQUIRE_PLUGIN
public void __pl_store_SetNTVOptional()
{
	MarkNativeAsOptional("Store_OpenMainMenu");
	MarkNativeAsOptional("Store_AddMainMenuItem");
	MarkNativeAsOptional("Store_GetCurrencyName");
}
#endif