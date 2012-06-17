#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <wamp>

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMPLib - Clients",
	author 		= "Thrawn",
	description = "Provides data about the clients",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_wamp_clients_version", VERSION, "", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
}

public OnAllPluginsLoaded() {
	wamp_register_rpc("http://sm#GetMaxClients", RPC_GetMaxClients);
	wamp_register_rpc("http://sm#GetClientsAdvanced", RPC_GetClientsAdvanced);
	wamp_register_channel("http://sm#ClientEvents", Channel_OnClientEvent);
}

public OnPluginEnd() {
	wamp_unregister_rpc("http://sm#GetMaxClients");
	wamp_unregister_rpc("http://sm#GetClientsAdvanced");
	wamp_unregister_channel("http://sm#ClientEvents");
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

public RPC_GetClientsAdvanced(Handle:hPlayerProps, &Handle:hResult) {
	hResult = json_object();
	for(new client = 1; client <= MaxClients; client++) {
		if(!IsClientInGame(client))continue;

		new String:cls[64];
		if(!GetEntityNetClass(client, cls, sizeof(cls)))continue;

		new Handle:hPlayerResult = json_array();
		for(new iPlayerProp = 0; iPlayerProp < json_array_size(hPlayerProps); iPlayerProp++) {
			new String:sProp[128];
			json_array_get_string(hPlayerProps, iPlayerProp, sProp, sizeof(sProp));

			new PropFieldType:type;
			FindSendPropInfo(cls, sProp, type);

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

		new String:sName[128];
		Format(sName, sizeof(sName), "%N", client);
		json_object_set_new(hResult, sName, hPlayerResult);
	}
}