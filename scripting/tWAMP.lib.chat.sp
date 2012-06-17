#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <wamp>

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMPLib - Chat",
	author 		= "Thrawn",
	description = "Provides a chat channel",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_wamp_chat_version", VERSION, "", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
}

public OnAllPluginsLoaded() {
	wamp_register_channel("http://sm#chat", Chat_OnPublish);

	AddCommandListener(OnSay, "say");
}

public OnPluginEnd() {
	wamp_unregister_channel("http://sm#chat");
}

public Action:OnSay(client, const String:command[], argc) {
	if(wamp_subscriptions("http://sm#chat") < 1) {
		return Plugin_Continue;
	}

	decl String:sBuffer[128];
	GetCmdArgString(sBuffer, sizeof(sBuffer));

	StripQuotes(sBuffer);
	if(strlen(sBuffer) == 0)return Plugin_Continue;

	new Handle:hArray = json_array();
	json_array_append_new(hArray, json_string_format("%N", client));
	json_array_append_new(hArray, json_string(sBuffer));

	wamp_publish("http://sm#chat", hArray);
	CloseHandle(hArray);

	return Plugin_Continue;
}

public Chat_OnPublish(Handle:hData, bool:bSelf) {
	if(bSelf)return;
	if(!json_is_array(hData))return;

	new String:sNick[64];
	new String:sMsg[128];
	if(json_array_get_string(hData, 0, sNick, sizeof(sNick)) == -1)return;
	if(json_array_get_string(hData, 1, sMsg, sizeof(sMsg)) == -1)return;

	PrintToServer("%s: %s", sNick, sMsg);
	PrintToChatAll("%s: %s", sNick, sMsg);
}