I have some questions!
======================

What is this?
--------------------------------------------
A server-side implementation of the [WAMP](http://wamp.ws "WAMP specification") specification for Sourcemod.
It basically allows to define RPC methods and create PubSub channels in SourceMod without having to worry about implementation specifics.


Why should i NOT run this?
--------------------------------------------
Because it's currently a project for fun only. At its current state I would not recommend running this on a productive server.


I don't care! What do I need?
--------------------------------------------
Ok, you know what you are doing. Links should be enough then.

* [Socket](http://forums.alliedmods.net/showthread.php?t=67640 "This extension provides networking functionality for SourceMod scripts.") extension.
* [Websocket](http://forums.alliedmods.net/showthread.php?t=182615 "[DEV] WebSocket Server - Direct connection between webbrowser and gameserver") plugin.
* [SMJansson](https://github.com/thraaawn/SMJansson "This extension wraps Jansson, a C library for encoding, decoding and manipulating JSON data") extension.


If this is server-side, how do I implement the client-side of all this?
----------------------------------------------------------------------------------------
You can use the [Autobahn.js](http://autobahn.ws/developers/autobahnjs "Open-Source (MIT License)") client library by [Tavendo](http://www.tavendo.de/ "Tavendo GmbH").
You should also take a look at some of the examples in the htdocs folder.


There is no documentation yet!?
--------------------------------------------

Indeed. Though there is not really much to know.

In a nutshell:

**It's all JSON**

* Use the [SMJansson](https://github.com/thraaawn/SMJansson "SMJansson") extension to read passed parameters and format results.

**Channels**

* Register a channel (those can't be shared atm, so use a unique name).
* The callback will fire everytime somebody published something in the channel, even if it was the plugin itself.
* Publish something to the channel.
* Un-register the channel on plugin end.

**RPC**

* Register a method.
* The callback will fire everytime the method is called. hResult must be a valid SMJansson handle.
* Un-register the method on plugin end.