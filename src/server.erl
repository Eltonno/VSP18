%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:45
%%%-------------------------------------------------------------------
-module(server).
-author("Elton").

-export([start/0,loop/7]).

-define(SERVER_LOGGING_FILE, "Server_" ++ atom_to_list(erlang:node()) ++ ".log").
-define(MAXIMAL_RESPONSE_TIME_BEFORE_ERROR, 10000).

start() ->

  {Latency, Clientlifetime, Servername, HBQname, HBQnode} = readConfig(),
  CMEM = cmem:initCMEM(Clientlifetime, ?SERVER_LOGGING_FILE),
  ServerPID = spawn(?MODULE,loop,[Latency,Clientlifetime,Servername,HBQname,HBQnode,CMEM,1]),
  register(Servername, ServerPID),
  util:logging(?SERVER_LOGGING_FILE, "Server wurde registriert\n"),
  {HBQname, HBQnode} ! {ServerPID, {request, initHBQ}}.

readConfig() ->
  {ok, Configfile} = file:consult("server.cfg"),
  {ok, Latency} = vsutil:get_config_value(latency, Configfile),
  {ok, Clientlifetime} = vsutil:get_config_value(clientlifetime, Configfile),
  {ok, Servername} = vsutil:get_config_value(servername, Configfile),
  {ok, HBQname} = vsutil:get_config_value(hbqname, Configfile),
  {ok, HBQnode} = vsutil:get_config_value(hbqnode, Configfile),


  {Latency, Clientlifetime, Servername, HBQname, HBQnode}.


loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, CMEM, INNR) ->
  receive
    {dropmessage, [NNr, Msg, TSclientout]} ->
      util:logging('server.log', util:to_String(NNr) ++ "\n"),
      {HBQname, HBQnode} ! {self(), {request, pushHBQ, [NNr, Msg, TSclientout]}},
      receive
        {reply, ok} ->
          ok
      end,
      loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, CMEM, INNR);
    {ClientPID, getmessages} ->
      util:logging(?SERVER_LOGGING_FILE, util:to_String(CMEM) ++ "\n"),
      {HBQname, HBQnode} ! {self(), {request, deliverMSG, cmem:getClientNNr(CMEM, ClientPID), ClientPID}},
      receive
        %%TODO: Hier kommt als SendNNr nicht 1 sondern ok an
        {reply, SendNNr} ->
          util:logging(?SERVER_LOGGING_FILE, util:to_String(SendNNr) ++ "\n"),
          NewCMEM = cmem:updateClient(CMEM, ClientPID, SendNNr, ?SERVER_LOGGING_FILE),
          loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, NewCMEM, INNR)
      end;
    {ClientPID, getmsgid} ->
      ClientPID ! {nid, INNR},
      loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, CMEM, INNR + 1)
  after
    Latency * 1000 ->
      {HBQname, HBQnode} ! {self(), {request, dellHBQ}},
      receive
        {reply, ok} ->
          util:logging(?SERVER_LOGGING_FILE, "HBQ wurde terminiert"),
          util:logging(?SERVER_LOGGING_FILE, "Server wurde terminiert"),
          ok
      end,
      util:logging(?SERVER_LOGGING_FILE, "Exterminated"),
      erlang:unregister(Servername)
  end.