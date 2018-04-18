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

-export([start/0,loop/8]).

-define(SERVER_LOGGING_FILE, "Server@" ++ os:getenv("USERDOMAIN")).
-define(MAXIMAL_RESPONSE_TIME_BEFORE_ERROR, 10000).

start() ->

  {Latency, Clientlifetime, Servername, HBQname, HBQnode} = readConfig(),
  CMEM = cmem:initCMEM(Clientlifetime, ?SERVER_LOGGING_FILE),
  ServerPID = spawn(?MODULE,loop,[Latency,Clientlifetime,Servername,HBQname,HBQnode,CMEM,1,erlang:timestamp()]),
  register(Servername, ServerPID),
  util:logging(?SERVER_LOGGING_FILE, "Server wurde registriert\n"),
  %%spawn(HBQnode, HBQname,
  HBQ = hbq:startHBQ(),
  %%[]),
  {HBQname, HBQnode} ! {request, initHBQ}
%%  util:logging(?SERVER_LOGGING_FILE,
%%    "Server hat die CMEM initializiert, der INHALT:" ++
%%      util:to_String(CMEM) ++
%%      "\n"
%%  )
.

readConfig() ->
  {ok, Configfile} = file:consult("server.cfg"),
  {ok, Latency} = vsutil:get_config_value(latency, Configfile),
  {ok, Clientlifetime} = vsutil:get_config_value(clientlifetime, Configfile),
  {ok, Servername} = vsutil:get_config_value(servername, Configfile),
  {ok, HBQname} = vsutil:get_config_value(hbqname, Configfile),
  {ok, HBQnode} = vsutil:get_config_value(hbqnode, Configfile),


  {Latency, Clientlifetime, Servername, HBQname, HBQnode}.


loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, CMEM, INNR, TimeOfLastConnection) ->


  case vsutil:getUTC() - vsutil:now2UTC(TimeOfLastConnection) < Latency of
    true ->
      receive

        {dropmessage, [NNr, Msg, TSclientout]} ->
          {HBQname, HBQnode} ! {self(), {request, pushHBQ, [NNr, Msg, TSclientout]}},
          receive
            {reply, ok} ->
              ok
          end,
          loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, CMEM, INNR, erlang:timestamp());
        {ClientPID, getmessages} ->
          NNr = cmem:getClientNNr(CMEM, ClientPID),
          {HBQname, HBQnode} ! {self(), {request, deliverMSG, NNr, ClientPID}},
          receive
            {reply, SendNNr} ->
              NewCMEM = cmem:updateClient(CMEM, ClientPID, SendNNr, ?SERVER_LOGGING_FILE),
              loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, NewCMEM, INNR, erlang:timestamp())
          end;
        {ClientPID, getmsgid} ->
          ClientPID ! {nid, INNR},
          NewCMEM = cmem:updateClient(CMEM, ClientPID, INNR, ?SERVER_LOGGING_FILE),
          loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, NewCMEM, INNR + 1, erlang:timestamp())
      end;
    false ->
      shutdownRoutine(HBQname, HBQnode),
      util:logging(?SERVER_LOGGING_FILE, "Exterminated"),
      erlang:unregister(Servername)

  end.


shutdownRoutine(HBQName, HBQNode) ->
  {HBQName, HBQNode} ! self(),
  receive
    {reply, ok} ->
      util:logging(?SERVER_LOGGING_FILE, "HBQ wurde terminiert"),
      util:logging(?SERVER_LOGGING_FILE, "Server wurde terminiert"),
      ok
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(?SERVER_LOGGING_FILE, "cant correct shutdown HBQ no answer try again"),
    shutdownRoutine(HBQName, HBQNode)
  end.