#pragma semicolon 1
#include <sourcemod>
#include <smjansson>
#include <websocket>
#include <wamp>
#include <smlib>

#define VERSION 		"0.0.1"

public Plugin:myinfo = {
	name 		= "WAMP, Core",
	author 		= "Thrawn",
	description = "WebSocket Application Messaging Protocol",
	version 	= VERSION,
};


// The handle to the master socket
new WebsocketHandle:g_hListenSocket = INVALID_WEBSOCKET_HANDLE;

new Handle:g_hCvarEnabled = INVALID_HANDLE;
new bool:g_bEnabled;

new Handle:g_hMethods = INVALID_HANDLE;
new Handle:g_hChannels = INVALID_HANDLE;

new Handle:g_WStore = INVALID_HANDLE;

public OnPluginStart() {
	CreateConVar("sm_wamp_version", VERSION, "WebSocket Application Messaging Protocol", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_hCvarEnabled = CreateConVar("sm_wamp_enable", "1", "Enable WAMP", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	HookConVarChange(g_hCvarEnabled, Cvar_Changed);

	g_hMethods = CreateTrie();
	g_hChannels = CreateTrie();
	g_WStore = CreateTrie();
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
	RegPluginLibrary("wamp");

	// (Un)register RPC methods
	CreateNative("wamp_register_rpc", Native_Register);
	CreateNative("wamp_unregister_rpc", Native_Unregister);

	// (Un)register Pub/Sub channels
	CreateNative("wamp_register_channel", Native_Register_Channel);
	CreateNative("wamp_unregister_channel", Native_Unregister_Channel);

	// Get the amount of subscribers to a channel
	CreateNative("wamp_subscriptions", Native_ChannelSubscriptions);

	// Publish a message in a channel
	CreateNative("wamp_publish", Native_Publish);

	// For authentication type plugins
	CreateNative("wamp_set_permissions", Native_SetPermissions);

	// For plugins requiring authentication
	CreateNative("wamp_get_permissions", Native_GetPermissions);


	return APLRes_Success;
}

public OnConfigsExecuted() {
	g_bEnabled = GetConVarBool(g_hCvarEnabled);
}

public Cvar_Changed(Handle:convar, const String:oldValue[], const String:newValue[]) {
	OnConfigsExecuted();
}



public OnAllPluginsLoaded() {
	decl String:sServerIP[40];
	new longip = GetConVarInt(FindConVar("hostip"));

	FormatEx(sServerIP, sizeof(sServerIP), "%d.%d.%d.%d", (longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF);

	LogMessage("Opening websocket at %s:12345", sServerIP);

	g_hListenSocket = Websocket_Open(sServerIP, 12345, OnWebsocketIncoming, OnWebsocketMasterError, OnWebsocketMasterClose);
}


public OnPluginEnd() {
	if(g_hListenSocket != INVALID_WEBSOCKET_HANDLE) {
		Websocket_Close(g_hListenSocket);
	}
}

public Action:OnWebsocketIncoming(WebsocketHandle:websocket, WebsocketHandle:newWebsocket, const String:remoteIP[], remotePort, String:protocols[256]) {
	if(!g_bEnabled)return Plugin_Handled;
	//LogMessage("Incoming websocket from %s:%i  (%s)", remoteIP, remotePort, protocols);

	strcopy(protocols, 255, "wamp");
	Websocket_HookChild(newWebsocket, OnWebsocketReceive, OnWebsocketDisconnect, OnChildWebsocketError);
	Websocket_HookReadyStateChange(newWebsocket, OnWebsocketReady);

	// Create WebsocketData store
	WStore_Create(newWebsocket);

	return Plugin_Continue;
}

public OnWebsocketReady(WebsocketHandle:websocket, WebsocketReadyState:readystate) {
	if(readystate == State_Open) {
		new String:sSessionId[16];
		String_GetRandom(sSessionId, sizeof(sSessionId), 16);

		WStore_SetSessionId(websocket, sSessionId);

		// Welcome the client
		new Handle:hJSON = CreateWampWelcome(sSessionId);
		Websocket_SendJSON(websocket, hJSON);
		CloseHandle(hJSON);
	}
}

Websocket_SendJSON(WebsocketHandle:websocket, Handle:hJSON, iStringSize=4096) {
	new String:sJSON[iStringSize];
	json_dump(hJSON, sJSON, iStringSize, 0);

	Websocket_Send(websocket, SendType_Text, sJSON);
	//PrintToServer("Message sent:\n%s", sJSON);
}

public OnWebsocketMasterError(WebsocketHandle:websocket, const errorType, const errorNum) {
	LogError("MASTER SOCKET ERROR: handle: %d type: %d, errno: %d", _:websocket, errorType, errorNum);
	g_hListenSocket = INVALID_WEBSOCKET_HANDLE;
	Wamp_RemoveSubscriptions(websocket);
	WStore_Destroy(websocket);
}

public OnWebsocketMasterClose(WebsocketHandle:websocket) {
	g_hListenSocket = INVALID_WEBSOCKET_HANDLE;
	Wamp_RemoveSubscriptions(websocket);
	WStore_Destroy(websocket);
}

public OnChildWebsocketError(WebsocketHandle:websocket, const errorType, const errorNum) {
	LogError("CHILD SOCKET ERROR: handle: %d, type: %d, errno: %d", _:websocket, errorType, errorNum);
	Wamp_RemoveSubscriptions(websocket);
	WStore_Destroy(websocket);
}


public OnWebsocketReceive(WebsocketHandle:websocket, WebsocketSendType:iType, const String:receiveData[], const dataSize) {
	if(!g_bEnabled)return;

	if(iType == SendType_Text) {
		new Handle:hJSON = json_load(receiveData);

		if(hJSON == INVALID_HANDLE) {
			LogError("Received data is no JSON.");
			return;
		}

		if(!json_is_array(hJSON)) {
			LogError("Received data is no JSON array.");
			return;
		}

		new Wamp_TypeId:msgType = Wamp_TypeId:json_array_get_int(hJSON, 0);
		switch(msgType) {
			case TYPE_ID_PREFIX: {
				new String:sPrefix[32];
				new String:sURI[512];
				if	( json_array_get_string(hJSON, 1, sPrefix, sizeof(sPrefix)) > 0 &&
					  json_array_get_string(hJSON, 2, sURI, sizeof(sURI)) > 0 ) {
					WStore_AddPrefix(websocket, sPrefix, sURI);
				}
			}

			case TYPE_ID_CALL: {
				new String:sCallId[32];
				new String:sProcURI[512];
				if	( json_array_get_string(hJSON, 1, sCallId, sizeof(sCallId)) > 0 &&
					  json_array_get_string(hJSON, 2, sProcURI, sizeof(sProcURI)) > 0 ) {
					// Incoming RPC Call
					// * validate && send errors
					// * take care of multiple arguments
					// * forward

					if(strlen(sProcURI) < 1) {
						new Handle:hReply = CreateWampError(sCallId, "InvalidRequest", "Method is empty.");
						Websocket_SendJSON(websocket, hReply);
						CloseHandle(hReply);
						return;
					}

					new String:sMethod[MAX_METHOD_NAME_LENGTH];
					if(strncmp(sProcURI, "http", 4, false) != 0) {
						// It's a CURIE
						new String:sPrefix[64];
						new iPos = SplitString(sProcURI, ":", sPrefix, sizeof(sPrefix));
						if(iPos < 1) {
							new Handle:hReply = CreateWampError(sCallId, "InvalidRequest", "CURIE prefix to short.");
							Websocket_SendJSON(websocket, hReply);
							CloseHandle(hReply);
							return;
						}

						new String:sURL[512];
						if(WStore_GetPrefix(websocket, sPrefix, sURL, sizeof(sURL)) < 1) {
							new Handle:hReply = CreateWampError(sCallId, "InvalidRequest", "CURIE prefix not registered.");
							Websocket_SendJSON(websocket, hReply);
							CloseHandle(hReply);
							return;
						}

						Format(sMethod, sizeof(sMethod), "%s%s", sURL, sProcURI[iPos]);
					} else {
						// It's URI
						strcopy(sMethod, sizeof(sMethod), sProcURI);
					}

					//LogMessage("RPC call to method '%s'", sMethod);

					new Handle:hMethodOptions = INVALID_HANDLE;
					if(!GetTrieValue(g_hMethods, sMethod, hMethodOptions)) {
						new Handle:hReply = CreateWampError(sCallId, "InvalidRequest", "Method not registered.");
						Websocket_SendJSON(websocket, hReply);
						CloseHandle(hReply);
						return;
					}

					new Function:cbMI;
					if(!GetTrieValue(hMethodOptions, "callback", cbMI)) {
						new Handle:hReply = CreateWampError(sCallId, "InternalError", "Method has no callback.");
						Websocket_SendJSON(websocket, hReply);
						CloseHandle(hReply);
						return;
					}

					new Handle:hMethodPlugin = INVALID_HANDLE;
					if(!GetTrieValue(hMethodOptions, "plugin", hMethodPlugin) || !IsValidPlugin(hMethodPlugin) || GetPluginStatus(hMethodPlugin) != Plugin_Running) {
						new Handle:hReply = CreateWampError(sCallId, "InternalError", "Method has no plugin.");
						Websocket_SendJSON(websocket, hReply);
						CloseHandle(hReply);
						return;
					}

					new Handle:hParams = json_array_get(hJSON, 3);

					new Handle:hResult = INVALID_HANDLE;

					Call_StartFunction(hMethodPlugin, cbMI);
					Call_PushCell(hParams);
					Call_PushCellRef(hResult);
					Call_PushCell(websocket);

					new iResult;
					Call_Finish(_:iResult);

					if(hParams != INVALID_HANDLE) {
						CloseHandle(hParams);
					}

					// Build response json
					new Handle:hReply = CreateWampResult(sCallId, hResult);
					Websocket_SendJSON(websocket, hReply);
					CloseHandle(hResult);
					CloseHandle(hReply);
				}
			}

			case TYPE_ID_SUBSCRIBE: {
				new String:sProcURI[512];
				if	(json_array_get_string(hJSON, 1, sProcURI, sizeof(sProcURI)) > 0) {
					if(strlen(sProcURI) < 1)return;

					new String:sChannel[MAX_METHOD_NAME_LENGTH];
					if(strncmp(sProcURI, "http", 4, false) != 0) {
						// It's a CURIE
						new String:sPrefix[64];
						new iPos = SplitString(sProcURI, ":", sPrefix, sizeof(sPrefix));
						if(iPos < 1) {
							return;
						}

						new String:sURL[512];
						if(WStore_GetPrefix(websocket, sPrefix, sURL, sizeof(sURL)) < 1) {
							return;
						}

						Format(sChannel, sizeof(sChannel), "%s%s", sURL, sProcURI[iPos]);
					} else {
						// It's URI
						strcopy(sChannel, sizeof(sChannel), sProcURI);
					}

					new Handle:hChannelOptions = INVALID_HANDLE;
					if(!GetTrieValue(g_hChannels, sChannel, hChannelOptions)) {
						return;
					}

					new Handle:hSubscriptions = INVALID_HANDLE;
					if(!GetTrieValue(hChannelOptions, "subscriptions", hSubscriptions)) {
						return;
					}

					if(FindValueInArray(hSubscriptions, websocket) > -1) {
						return;
					}

					LogMessage("A client registered for: %s", sChannel);
					WStore_AddSubscription(websocket, sChannel);
					PushArrayCell(hSubscriptions, websocket);
				}

			}

			case TYPE_ID_UNSUBSCRIBE: {
				new String:sProcURI[512];
				if	(json_array_get_string(hJSON, 1, sProcURI, sizeof(sProcURI)) > 0) {
					if(strlen(sProcURI) < 1)return;

					new String:sChannel[MAX_METHOD_NAME_LENGTH];
					if(strncmp(sProcURI, "http", 4, false) != 0) {
						// It's a CURIE
						new String:sPrefix[64];
						new iPos = SplitString(sProcURI, ":", sPrefix, sizeof(sPrefix));
						if(iPos < 1) {
							return;
						}

						new String:sURL[512];
						if(WStore_GetPrefix(websocket, sPrefix, sURL, sizeof(sURL)) < 1) {
							return;
						}

						Format(sChannel, sizeof(sChannel), "%s%s", sURL, sProcURI[iPos]);
					} else {
						// It's URI
						strcopy(sChannel, sizeof(sChannel), sProcURI);
					}

					new Handle:hChannelOptions = INVALID_HANDLE;
					if(!GetTrieValue(g_hChannels, sChannel, hChannelOptions)) {
						return;
					}

					new Handle:hSubscriptions = INVALID_HANDLE;
					if(!GetTrieValue(hChannelOptions, "subscriptions", hSubscriptions)) {
						return;
					}

					new iIndex = FindValueInArray(hSubscriptions, websocket);
					if(iIndex == -1) {
						return;
					}

					RemoveFromArray(hSubscriptions, iIndex);
				}
			}

			case TYPE_ID_PUBLISH: {
				new String:sProcURI[512];
				if	(json_array_get_string(hJSON, 1, sProcURI, sizeof(sProcURI)) > 0) {
					if(strlen(sProcURI) < 1)return;

					new String:sChannel[MAX_METHOD_NAME_LENGTH];
					if(strncmp(sProcURI, "http", 4, false) != 0) {
						// It's a CURIE
						new String:sPrefix[64];
						new iPos = SplitString(sProcURI, ":", sPrefix, sizeof(sPrefix));
						if(iPos < 1) {
							return;
						}

						new String:sURL[512];
						if(WStore_GetPrefix(websocket, sPrefix, sURL, sizeof(sURL)) < 1) {
							return;
						}

						Format(sChannel, sizeof(sChannel), "%s%s", sURL, sProcURI[iPos]);
					} else {
						// It's URI
						strcopy(sChannel, sizeof(sChannel), sProcURI);
					}

					new Handle:hChannelOptions = INVALID_HANDLE;
					if(!GetTrieValue(g_hChannels, sChannel, hChannelOptions)) {
						return;
					}

					new Handle:hSubscriptions = INVALID_HANDLE;
					if(!GetTrieValue(hChannelOptions, "subscriptions", hSubscriptions)) {
						return;
					}

					new bool:bIsListener = (FindValueInArray(hSubscriptions, websocket) != -1);

					// TODO:
					// * Call forward
					// * Send to all other clients
					new Handle:hEvent = json_array_get(hJSON, 2);

					new Function:cbOnPublish;
					if(!GetTrieValue(hChannelOptions, "callback", cbOnPublish)) {
						return;
					}

					new Handle:hChannelPlugin = INVALID_HANDLE;
					if(!GetTrieValue(hChannelOptions, "plugin", hChannelPlugin) || !IsValidPlugin(hChannelPlugin) || GetPluginStatus(hChannelPlugin) != Plugin_Running) {
						return;
					}

					Call_StartFunction(hChannelPlugin, cbOnPublish);
					Call_PushCell(hEvent);
					Call_PushCell(false);

					new iResult;
					Call_Finish(_:iResult);

					new bool:bExcludeSelf = false;
					if(json_array_size(hJSON) == 4) {
						new Handle:hExcludeMe = json_array_get(hJSON, 3);
						bExcludeSelf = json_is_true(hExcludeMe);
						CloseHandle(hExcludeMe);
					}

					new iSubscriberCount = GetArraySize(hSubscriptions);
					if(bIsListener && bExcludeSelf)iSubscriberCount--;

					// Build response json
					new Handle:hReply = CreateWampEvent(sChannel, hEvent);
					new String:sJSON[4096];
					json_dump(hReply, sJSON, sizeof(sJSON), 0);
					CloseHandle(hReply);

					if(iSubscriberCount > 0) {
						for(new iSubscriber = 0; iSubscriber < GetArraySize(hSubscriptions); iSubscriber++) {
							new WebsocketHandle:wSubscriber = GetArrayCell(hSubscriptions, iSubscriber);
							if(bExcludeSelf && wSubscriber == websocket)continue;
							Websocket_Send(wSubscriber, SendType_Text, sJSON);
						}
					}
				}
			}
		}

	}
}

public OnResponseReady(const String:sResponse[], any:websocket) {
	Websocket_Send(websocket, SendType_Text, sResponse);
}

public OnWebsocketDisconnect(WebsocketHandle:websocket) {
	Wamp_RemoveSubscriptions(websocket);
	WStore_Destroy(websocket);
}

Wamp_RemoveSubscriptions(WebsocketHandle:websocket) {
	new Handle:hChannels = WStore_GetSubscriptions(websocket);
	if(hChannels == INVALID_HANDLE)return;

	for(new iChannel = 0; iChannel < GetArraySize(hChannels); iChannel++) {
		new String:sChannel[128];
		GetArrayString(hChannels, iChannel, sChannel, sizeof(sChannel));

		new Handle:hChannelOptions = INVALID_HANDLE;
		GetTrieValue(g_hChannels, sChannel, hChannelOptions);

		if(hChannelOptions == INVALID_HANDLE) {
			return;
		}

		new Handle:hSubscriptions = INVALID_HANDLE;
		if(!GetTrieValue(hChannelOptions, "subscriptions", hSubscriptions) || hSubscriptions == INVALID_HANDLE) {
			return;
		}

		new iIndex = FindValueInArray(hSubscriptions, websocket);
		if(iIndex > -1)  {
			RemoveFromArray(hSubscriptions, iIndex);
		}
	}
}



Handle:CreateWampEvent(String:sChannel[], Handle:hData) {
	new Handle:hResponse = json_array();
	json_array_append_new(hResponse, json_integer(_:TYPE_ID_EVENT));
	json_array_append_new(hResponse, json_string(sChannel));
	if(hData == INVALID_HANDLE) {
		json_array_append_new(hResponse, json_null());
	} else {
		json_array_append(hResponse, hData);
	}

	return hResponse;
}

Handle:CreateWampResult(String:sCallId[], Handle:hResult) {
	new Handle:hResponse = json_array();
	json_array_append_new(hResponse, json_integer(_:TYPE_ID_CALLRESULT));
	json_array_append_new(hResponse, json_string(sCallId));
	if(hResult != INVALID_HANDLE) {
		json_array_append(hResponse, hResult);
	}

	return hResponse;
}

Handle:CreateWampError(String:sCallId[], String:sErrorUri[], String:sErrorDescription[], Handle:hErrorDetails = INVALID_HANDLE) {
	new Handle:hResponse = json_array();
	json_array_append_new(hResponse, json_integer(_:TYPE_ID_CALLERROR));
	json_array_append_new(hResponse, json_string(sCallId));
	json_array_append_new(hResponse, json_string_format("http://sourcemod.net/WAMP/Error/%s",sErrorUri));
	json_array_append_new(hResponse, json_string(sErrorDescription));

	if(hErrorDetails != INVALID_HANDLE) {
		json_array_append_new(hResponse, hErrorDetails);
	}

	return hResponse;
}

Handle:CreateWampWelcome(String:sCallId[]) {
	new Handle:hResponse = json_array();
	json_array_append_new(hResponse, json_integer(_:TYPE_ID_WELCOME));
	json_array_append_new(hResponse, json_string(sCallId));
	json_array_append_new(hResponse, json_integer(WAMP_PROTOCOL_VERSION));
	json_array_append_new(hResponse, json_string_format("tWAMP/%s", VERSION));

	return hResponse;
}





// native wamp_register_rpc(const String:sMethod[], MethodInvocationCallback:cbMI);
public Native_Register(Handle:hPlugin, iNumParams) {
	new String:sMethod[MAX_METHOD_NAME_LENGTH];
	GetNativeString(1, sMethod, sizeof(sMethod));

	new Function:cbMI = GetNativeCell(2);

	new Handle:hMethodOptions = CreateTrie();
	SetTrieValue(hMethodOptions, "callback", cbMI);
	SetTrieValue(hMethodOptions, "plugin", hPlugin);

	SetTrieValue(g_hMethods, sMethod, hMethodOptions);
}

// native wamp_unregister_rpc(const String:sMethod[]);
public Native_Unregister(Handle:hPlugin, iNumParams) {
	new String:sMethod[MAX_METHOD_NAME_LENGTH];
	GetNativeString(1, sMethod, sizeof(sMethod));

	new Handle:hMethodOptions = INVALID_HANDLE;
	GetTrieValue(g_hMethods, sMethod, hMethodOptions);

	if(hMethodOptions != INVALID_HANDLE) {
		CloseHandle(hMethodOptions);
		RemoveFromTrie(g_hMethods, sMethod);
	}
}


// native wamp_register_channel(const String:sChannel[], ChannelCallback:cbOnPublish);
public Native_Register_Channel(Handle:hPlugin, iNumParams) {
	new String:sChannel[MAX_METHOD_NAME_LENGTH];
	GetNativeString(1, sChannel, sizeof(sChannel));

	new Function:cbOnPublish = GetNativeCell(2);

	new Handle:hSubscriptions = CreateArray(4);
	new Handle:hChannelOptions = CreateTrie();
	SetTrieValue(hChannelOptions, "subscriptions", hSubscriptions);
	SetTrieValue(hChannelOptions, "callback", cbOnPublish);
	SetTrieValue(hChannelOptions, "plugin", hPlugin);

	SetTrieValue(g_hChannels, sChannel, hChannelOptions);
}

// native wamp_unregister_channel(const String:sChannel[]);
public Native_Unregister_Channel(Handle:hPlugin, iNumParams) {
	new String:sChannel[MAX_METHOD_NAME_LENGTH];
	GetNativeString(1, sChannel, sizeof(sChannel));

	new Handle:hChannelOptions = INVALID_HANDLE;
	GetTrieValue(g_hChannels, sChannel, hChannelOptions);

	if(hChannelOptions != INVALID_HANDLE) {
		CloseHandle(hChannelOptions);
		RemoveFromTrie(g_hChannels, sChannel);
	}
}

// native wamp_subscriptions(const String:sChannel[]);
public Native_ChannelSubscriptions(Handle:hPlugin, iNumParams) {
	new String:sChannel[MAX_METHOD_NAME_LENGTH];
	GetNativeString(1, sChannel, sizeof(sChannel));

	new Handle:hChannelOptions = INVALID_HANDLE;
	GetTrieValue(g_hChannels, sChannel, hChannelOptions);

	if(hChannelOptions != INVALID_HANDLE) {
		// Count all subscribers
		new Handle:hSubscriptions = INVALID_HANDLE;
		if(GetTrieValue(hChannelOptions, "subscriptions", hSubscriptions) && hSubscriptions != INVALID_HANDLE) {
			return GetArraySize(hSubscriptions);
		}
	}

	return -1;
}

// native bool:wamp_publish(const String:sChannel[], Handle:hData)
public Native_Publish(Handle:hPlugin, iNumParams) {
	new String:sChannel[MAX_METHOD_NAME_LENGTH];
	GetNativeString(1, sChannel, sizeof(sChannel));

	new Handle:hData = GetNativeCell(2);

	new Handle:hChannelOptions = INVALID_HANDLE;
	GetTrieValue(g_hChannels, sChannel, hChannelOptions);

	if(hChannelOptions == INVALID_HANDLE) {
		return false;
	}

	new Handle:hSubscriptions = INVALID_HANDLE;
	if(!GetTrieValue(hChannelOptions, "subscriptions", hSubscriptions) || hSubscriptions == INVALID_HANDLE) {
		return false;
	}

	new Function:cbOnPublish;
	if(!GetTrieValue(hChannelOptions, "callback", cbOnPublish)) {
		return false;
	}

	new Handle:hChannelPlugin = INVALID_HANDLE;
	if(!GetTrieValue(hChannelOptions, "plugin", hChannelPlugin) || !IsValidPlugin(hChannelPlugin) || GetPluginStatus(hChannelPlugin) != Plugin_Running) {
		return false;
	}

	Call_StartFunction(hChannelPlugin, cbOnPublish);
	Call_PushCell(hData);
	Call_PushCell(true);

	new iResult;
	Call_Finish(_:iResult);

	new iSubscriberCount = GetArraySize(hSubscriptions);
	if(iSubscriberCount == 0) {
		return true;
	}

	// Build response json
	new Handle:hReply = CreateWampEvent(sChannel, hData);
	new String:sJSON[4096];
	json_dump(hReply, sJSON, sizeof(sJSON), 0);
	CloseHandle(hReply);

	for(new iSubscriber = 0; iSubscriber < iSubscriberCount; iSubscriber++) {
		new WebsocketHandle:websocket = GetArrayCell(hSubscriptions, iSubscriber);

		Websocket_Send(websocket, SendType_Text, sJSON);
	}

	return true;
}

// native wamp_set_permissions(WebsocketHandle:hWebsocket, iFlags);
public Native_SetPermissions(Handle:hPlugin, iNumParams) {
	new WebsocketHandle:websocket = GetNativeCell(1);
	new iFlags = GetNativeCell(2);

	return WStore_SetPermissions(websocket, iFlags);
}

// native wamp_get_permissions(WebsocketHandle:hWebsocket);
public Native_GetPermissions(Handle:hPlugin, iNumParams) {
	new WebsocketHandle:websocket = GetNativeCell(1);

	return WStore_GetPermissions(websocket);
}


/* Websocket Store stuff */

WStore_Create(WebsocketHandle:websocket) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	// Initialize WebsocketData
	new Handle:hWebSocketData = CreateTrie();

	// Initialize all custom data and store in WebsocketData
	SetTrieValue(hWebSocketData, "prefixes", CreateTrie());
	SetTrieValue(hWebSocketData, "subscriptions", CreateArray(64));

	// Store WebsocketData in Global Store by WebsocketHandle
	SetTrieValue(g_WStore, sIndex, hWebSocketData);
}

WStore_Destroy(WebsocketHandle:websocket) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return;

	// Remove the container from the global Store
	RemoveFromTrie(g_WStore, sIndex);

	// Remove all custom data
	WStore_CloseData(hWebSocketData, "prefixes");
	WStore_CloseData(hWebSocketData, "subscriptions");

	// Close the custom data container
	CloseHandle(hWebSocketData);
}

WStore_CloseData(Handle:hWebSocketData, const String:sKey[]) {
	new Handle:hValue = INVALID_HANDLE;
	GetTrieValue(hWebSocketData, sKey, hValue);

	if(hValue != INVALID_HANDLE) {
		CloseHandle(hValue);
	}
}

WStore_AddSubscription(WebsocketHandle:websocket, const String:sChannel[]) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return;

	new Handle:hSubscriptions = INVALID_HANDLE;
	GetTrieValue(hWebSocketData, "subscriptions", hSubscriptions);

	if(hSubscriptions != INVALID_HANDLE) {
		if(FindStringInArray(hSubscriptions, sChannel) > -1) {
			return;
		}

		PushArrayString(hSubscriptions, sChannel);
	}
}

Handle:WStore_GetSubscriptions(WebsocketHandle:websocket) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return hWebSocketData;

	new Handle:hSubscriptions = INVALID_HANDLE;
	GetTrieValue(hWebSocketData, "subscriptions", hSubscriptions);

	return hSubscriptions;
}

WStore_AddPrefix(WebsocketHandle:websocket, const String:sPrefix[], const String:sURI[]) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return;

	new Handle:hPrefixes = INVALID_HANDLE;
	GetTrieValue(hWebSocketData, "prefixes", hPrefixes);

	if(hPrefixes != INVALID_HANDLE) {
		SetTrieString(hPrefixes, sPrefix, sURI);
		//LogMessage("New prefix: %s --> %s", sPrefix, sURI);
	}
}

WStore_GetPrefix(WebsocketHandle:websocket, const String:sPrefix[], String:sURI[], maxlength) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return -1;

	new Handle:hPrefixes = INVALID_HANDLE;
	GetTrieValue(hWebSocketData, "prefixes", hPrefixes);

	if(hPrefixes != INVALID_HANDLE) {
		new iSize;
		if(GetTrieString(hPrefixes, sPrefix, sURI, maxlength, iSize)) {
			return iSize;
		}
	}

	return -1;
}


WStore_SetSessionId(WebsocketHandle:websocket, const String:sSessionId[]) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return;

	SetTrieString(hWebSocketData, "SessionId", sSessionId);
}

WStore_GetSessionId(WebsocketHandle:websocket, String:sSessionId[], maxlength) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return;

	GetTrieString(hWebSocketData, "SessionId", sSessionId, maxlength);
}


bool:WStore_SetPermissions(WebsocketHandle:websocket, flags) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return false;

	return SetTrieValue(hWebSocketData, "Flags", flags);
}

WStore_GetPermissions(WebsocketHandle:websocket) {
	new String:sIndex[10];
	IntToString(_:websocket, sIndex, sizeof(sIndex));

	new Handle:hWebSocketData = INVALID_HANDLE;
	GetTrieValue(g_WStore, sIndex, hWebSocketData);

	if(hWebSocketData == INVALID_HANDLE)return -1;

	new iFlags;
	if(!GetTrieValue(hWebSocketData, "Flags", iFlags)) {
		return -1;
	}

	return iFlags;
}




// IsValidHandle() is deprecated, let's do a real check then...
stock bool:IsValidPlugin(Handle:hPlugin) {
	if(hPlugin == INVALID_HANDLE)return false;

	new Handle:hIterator = GetPluginIterator();

	new bool:bPluginExists = false;
	while(MorePlugins(hIterator)) {
		new Handle:hLoadedPlugin = ReadPlugin(hIterator);
		if(hLoadedPlugin == hPlugin) {
			bPluginExists = true;
			break;
		}
	}

	CloseHandle(hIterator);

	return bPluginExists;
}