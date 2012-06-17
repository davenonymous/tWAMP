#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <wamp>

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMPLib - Entities",
	author 		= "Thrawn",
	description = "Provides data about entities",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_wamp_entities_version", VERSION, "", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

}

public OnAllPluginsLoaded() {
	wamp_register_rpc("http://sm#GetEntities", RPC_GetEntities);
}

public OnPluginEnd() {
	wamp_unregister_rpc("http://sm#GetEntities");
}


public RPC_GetEntities(Handle:hParams, &Handle:hResult) {
	new iOffset = 0;
	new iLimit = 10;

	if(json_is_object(hParams)) {
		iOffset = json_object_get_int(hParams, "offset");
		iLimit = json_object_get_int(hParams, "limit");
	}
	LogMessage("Got call from: %i", iOffset);

	new Handle:hResultArray = json_array();

	new iMaxEntities = GetMaxEntities();
	new iEntity = iOffset;
	new iCount = 0;
	while(iCount < iLimit && iEntity < iMaxEntities) {
		if(!IsValidEntity(iEntity)) {
			iEntity++;
			continue;
		}

		new Handle:hEntity = json_object();
		json_object_set_new(hEntity, "index", json_integer(iEntity));

		new String:sClassName[128];
		if(GetEntityClassname(iEntity, sClassName, sizeof(sClassName))) {
			json_object_set_new(hEntity, "classname", json_string(sClassName));
		}

		new String:sNetClass[128];
		if(GetEntityNetClass(iEntity, sNetClass, sizeof(sNetClass))) {
			json_object_set_new(hEntity, "netclass", json_string(sNetClass));
		}

		json_array_append_new(hResultArray, hEntity);
		iCount++;
		iEntity++;
	}


	hResult = json_object();
	json_object_set_new(hResult, "data", hResultArray);
	json_object_set_new(hResult, "nextid", json_integer(iEntity >= iMaxEntities ? -1 : iEntity));
}