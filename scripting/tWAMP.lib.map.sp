#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <wamp>
#include <regex>

new Handle:g_RegExBSP;

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMPLib - Mapcycle",
	author 		= "Thrawn",
	description = "Provides data about the mapcycle",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_wamp_map_version", VERSION, "", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_RegExBSP = CompileRegex("(.*)\\.bsp$");
}

public OnAllPluginsLoaded() {
	wamp_register_rpc("http://sm#ChangeLevel", RPC_Changelevel);
	wamp_register_rpc("http://sm#GetCurrentMap", RPC_GetCurrentMap);
	wamp_register_rpc("http://sm#GetAvailableMaps", RPC_GetAvailableMaps);
	wamp_register_channel("http://sm#ServerEvents", Channel_OnMapStart);
}

public OnPluginEnd() {
	wamp_unregister_rpc("http://sm#ChangeLevel");
	wamp_unregister_rpc("http://sm#GetCurrentMap");
	wamp_unregister_rpc("http://sm#GetAvailableMaps");
	wamp_unregister_channel("http://sm#ServerEvents");
}

public OnMapStart() {
	if(wamp_subscriptions("http://sm#ServerEvents") < 1) {
		return;
	}

	new String:sMap[128];
	GetCurrentMap(sMap, sizeof(sMap));

	new Handle:hArray = json_array();
	json_array_append_new(hArray, json_string("OnMapStart"));
	json_array_append_new(hArray, json_string(sMap));

	wamp_publish("http://sm#ServerEvents", hArray);
	CloseHandle(hArray);
}

public Channel_OnMapStart(Handle:hData, bool:bSelf) {
	return;
}

public RPC_Changelevel(Handle:hParams, &Handle:hResult) {
	if(!json_is_string(hParams)) {
		hResult = INVALID_HANDLE;
		return;
	}

	new String:sMap[128];
	json_string_value(hParams, sMap, sizeof(sMap));

	ForceChangeLevel(sMap, "WAMP rpc call");
	hResult = json_boolean(true);
}

public RPC_GetCurrentMap(Handle:hParams, &Handle:hResult) {
	new String:sMap[128];
	GetCurrentMap(sMap, sizeof(sMap));

	hResult = json_string(sMap);
}

public RPC_GetAvailableMaps(Handle:hParams, &Handle:hResult) {
	hResult = json_array();

	new Handle:hDir = OpenDirectory("maps");
	new String:sEntry[PLATFORM_MAX_PATH];
	new FileType:xFileType;
	while(ReadDirEntry(hDir, sEntry, sizeof(sEntry), xFileType)) {
		if(xFileType == FileType_Directory)continue;

		if(MatchRegex(g_RegExBSP, sEntry)) {
			new String:sMap[PLATFORM_MAX_PATH];
			GetRegexSubString(g_RegExBSP, 1, sMap, sizeof(sMap));

			json_array_append_new(hResult, json_string(sMap));
		}
	}

	CloseHandle(hDir);
}
