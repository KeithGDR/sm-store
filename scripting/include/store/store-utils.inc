#if defined _store_utils_included
  #endinput
#endif
#define _store_utils_included

stock void Store_PrintToChat(int client, const char[] format, any ...) {
	char buffer[255];
	VFormat(buffer, sizeof(buffer), format, 3);

	if (client == 0) {
		PrintToServer("%s %s", STORE_PREFIX_CONSOLE, buffer);
	} else {
		CPrintToChat(client, "%s %s", STORE_PREFIX, buffer);
	}
}

stock void Store_PrintToChatAll(const char[] format, any ...) {
	char buffer[255];
	VFormat(buffer, sizeof(buffer), format, 2);

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}

		Store_PrintToChat(i, buffer);
	}
}

stock void Store_PrintToChatEx(int client, int author, const char[] format, any ...) {
	char buffer[255];
	VFormat(buffer, sizeof(buffer), format, 4);

	CPrintToChatEx(client, author, "%s %s", STORE_PREFIX, buffer);
}

stock void Store_PrintToChatAllEx(int author, const char[] format, any ...) {
	char buffer[255];
	VFormat(buffer, sizeof(buffer), format, 3);

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}

		Store_PrintToChatEx(i, author, buffer);
	}
}