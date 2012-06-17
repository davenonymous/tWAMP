#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <wamp>

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMPAuth - RCON",
	author 		= "Thrawn",
	description = "Authenticate via rcon password",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_wamp_auth_rcon_version", VERSION, "Authenticate via rcon password", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
}

public OnAllPluginsLoaded() {
	wamp_register_rpc("http://sm#LoginByRcon", RPC_LoginByRcon);
}

public OnPluginEnd() {
	wamp_unregister_rpc("http://sm#LoginByRcon");
}


public RPC_LoginByRcon(Handle:hParams, &Handle:hResult, WebsocketHandle:hCallingWebsocket) {
	if(!json_is_string(hParams)) {
		hResult = json_null();
		return;
	}

	new String:sPassword[255];
	json_string_value(hParams, sPassword, sizeof(sPassword));

	new String:sRcon[255];
	GetConVarString(FindConVar("rcon_password"), sRcon, sizeof(sRcon));

	if(StrEqual(sRcon, sPassword)) {
		wamp_set_permissions(hCallingWebsocket, ADMFLAG_ROOT);
		hResult = json_true();
	} else {
		wamp_set_permissions(hCallingWebsocket, 0);
		hResult = json_false();
	}
}