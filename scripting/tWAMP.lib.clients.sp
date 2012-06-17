#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <wamp>
#include <regex>

new Handle:g_RegExBSP;

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMPLib - Clients",
	author 		= "Thrawn",
	description = "Provides data about the clients",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_wamp_clients_version", VERSION, "", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_RegExBSP = CompileRegex("(.*)\\.bsp$");
}

public OnAllPluginsLoaded() {
	wamp_register_rpc("http://sm#GetMaxClients", RPC_GetMaxClients);
	wamp_register_rpc("http://sm#GetClientsAdvanced", RPC_GetClientsAdvanced);
	wamp_register_channel("http://sm#ClientEvents", Channel_OnClientEvent);
	/*
	wamp_register_rpc("http://sm#GetCurrentMap", RPC_GetCurrentMap);
	wamp_register_rpc("http://sm#GetAvailableMaps", RPC_GetAvailableMaps);
	wamp_register_channel("http://sm#ServerEvents", Channel_OnMapStart);
	*/
}

public OnPluginEnd() {
	wamp_unregister_rpc("http://sm#GetMaxClients");
	/*
	wamp_unregister_rpc("http://sm#GetCurrentMap");
	wamp_unregister_rpc("http://sm#GetAvailableMaps");
	wamp_unregister_channel("http://sm#ServerEvents");
	*/
}

public OnClientAuthorized(client, const String:auth[]) {
	if(wamp_subscriptions("http://sm#ClientEvents") < 1) {
		return;
	}

	new Handle:hArray = json_array();
	json_array_append_new(hArray, json_string("join"));
	json_array_append_new(hArray, json_string_format("%N", client));
	json_array_append_new(hArray, json_string(auth));

	wamp_publish("http://sm#ClientEvents", hArray);
	CloseHandle(hArray);
}

public Channel_OnClientEvent(Handle:hData, bool:bSelf) {
	return;
}

public RPC_GetMaxClients(Handle:hParams, &Handle:hResult) {
	hResult = json_integer(MaxClients);
}

public RPC_GetClientsAdvanced(Handle:hParams, &Handle:hResult) {
	new Handle:hPlayerProps = json_array_get(hParams, 0);
	new Handle:hScoreboardProps = json_array_get(hParams, 1);

	hResult = json_array();
	for(new client = 1; client <= MaxClients; client++) {
		if(IsClientInGame(client)) {
			new Handle:hPlayerResult = json_array();
			for(new iPlayerProp = 0; iPlayerProp < json_array_size(hPlayerProps); iPlayerProp++) {
				new String:sProp[128];
				json_array_get_string(hPlayerProps, iPlayerProp, sProp, sizeof(sProp));

				new PropFieldType:type;
				new iOffset = FindSendPropInfo("TFPlayer", sProp, type);

				new Handle:hValue;
				switch(type) {
					case PropField_Integer: {
						new iValue = GetEntProp(client, Prop_Send, sProp);
						hValue = json_integer(iValue);
					}

					case PropField_Vector: {
						new Float:vVector[3];
						GetEntPropVector(client, Prop_Send, sProp, vVector);

						hValue = json_array();
						json_array_append_new(hValue, json_real(vVector[0]));
						json_array_append_new(hValue, json_real(vVector[1]));
						json_array_append_new(hValue, json_real(vVector[2]));
					}

					case PropField_Float: {
						new Float:fValue = GetEntPropFloat(client, Prop_Send, sProp);
						hValue = json_real(fValue);
					}

					case PropField_String: {
						new String:sValue[128];
						GetEntPropString(client, Prop_Send, sProp, sValue, sizeof(sValue));
						hValue = json_string(sValue);
					}

					default: {
						hValue = json_null();
					}
				}

				json_array_append_new(hPlayerResult, hValue);
			}

			json_array_append(hResult,
		}
	}


	CloseHandle(hPlayerProps);
	CloseHandle(hScoreboardProps);

}

/*
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
*/