#if defined _wamp_included_
	#endinput
#endif
#define _wamp_included_

#define WAMP_PROTOCOL_VERSION	1

#define MAX_JSON_SIZE				4096
#define MAX_METHOD_NAME_LENGTH		256

enum Wamp_TypeId {
	TYPE_ID_WELCOME,
	TYPE_ID_PREFIX,
	TYPE_ID_CALL,
	TYPE_ID_CALLRESULT,
	TYPE_ID_CALLERROR,
	TYPE_ID_SUBSCRIBE,
	TYPE_ID_UNSUBSCRIBE,
	TYPE_ID_PUBLISH,
	TYPE_ID_EVENT
}

stock bool:Stringify_Wamp_TypeId(Wamp_TypeId:in, String:out[], maxlength) {
	switch(in) {
		case TYPE_ID_WELCOME: strcopy(out, maxlength, "Welcome");
		case TYPE_ID_PREFIX: strcopy(out, maxlength, "Prefix");
		case TYPE_ID_CALL: strcopy(out, maxlength, "Call");
		case TYPE_ID_CALLRESULT: strcopy(out, maxlength, "Call Result");
		case TYPE_ID_CALLERROR: strcopy(out, maxlength, "Call Error");
		case TYPE_ID_SUBSCRIBE: strcopy(out, maxlength, "Subscribe");
		case TYPE_ID_UNSUBSCRIBE: strcopy(out, maxlength, "Unsubscribe");
		case TYPE_ID_PUBLISH: strcopy(out, maxlength, "Publish");
		case TYPE_ID_EVENT: strcopy(out, maxlength, "Event");
		default: return false;
	}

	return true;
}

functag MethodInvocationCallback public(Handle:hJsonParams, &Handle:hResponse);
functag OnPublishCallback public(Handle:hData, bool:bSelf);

native wamp_register_rpc(const String:sMethod[], MethodInvocationCallback:cbMI);
native wamp_unregister_rpc(const String:sMethod[]);

native wamp_register_channel(const String:sChannel[], OnPublishCallback:cbOnPublish);
native wamp_unregister_channel(const String:sChannel[]);
native wamp_publish(const String:sChannel[], Handle:hJSON);
native wamp_subscriptions(const String:sChannel[]);