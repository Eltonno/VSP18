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

-export([start/0]).

-define(SERVER_LOGGING_FILE, "Server@" ++ os:getenv("USERDOMAIN")).
-define(MAXIMAL_RESPONSE_TIME_BEFORE_ERROR, 5000).

initHBQ(HBQname, HBQnode) ->
  {HBQname, HBQnode} ! {self(), {request, initHBQ}},
  receive
    {reply, ok} ->
      util:logging(?SERVER_LOGGING_FILE, "HBQ und DLQ wurden intialisiert")
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(?SERVER_LOGGING_FILE, "HBQ und DLQ wurden nicht initialisiert. Fehler!")
  end.

start() ->

  {Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit} = readConfig(),
  erlang:register(Servername, self()),
  util:logging(?SERVER_LOGGING_FILE, "Server wurde registriert"),
  net_adm:ping(HBQnode),
  initHBQ(HBQname, HBQnode),
  CMEM = cmem:initCMEM(Clientlifetime, ?SERVER_LOGGING_FILE),

  util:logging(?SERVER_LOGGING_FILE,
    "Server hat die CMEM initializiert, der INHALT:" ++
      util:to_String(CMEM) ++
      "\n"
  ),


  loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit, CMEM, 1, ?SERVER_LOGGING_FILE, erlang:timestamp()).

readConfig() ->

  {ok, ConfigListe} = file:consult("server.cfg"),
  {ok, Latency} = vsutil:get_config_value(latency, ConfigListe),
  {ok, Clientlifetime} = vsutil:get_config_value(clientlifetime, ConfigListe),
  {ok, Servername} = vsutil:get_config_value(servername, ConfigListe),
  {ok, DLQlimit} = vsutil:get_config_value(dlqlimit, ConfigListe),
  {ok, HBQname} = vsutil:get_config_value(hbqname, ConfigListe),
  {ok, HBQnode} = vsutil:get_config_value(hbqnode, ConfigListe),


  {Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit}.


loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit, CMEM, INNR, TimeOfLastConnection) ->


  case vsutil:getUTC() - vsutil:now2UTC(TimeOfLastConnection) < Latency of
    true ->
      receive

        {dropmessage, [NNr, Msg, TSclientout]} ->
          {HBQname, HBQnode} ! {self(), {request, pushHBQ, [NNr, Msg, TSclientout]}},
          receive
            {reply, ok} ->
              ok
          end,
          loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit, _CMEM, INNR, erlang:timestamp());
        {ClientPID, getmessages} ->
          NNr = cmem:getClientNNr(CMEM, ClientPID),

          {HBQname, HBQnode} ! {self(), {request, deliverMSG, NNr, ClientPID}},
          receive
            {reply, SendNNr} ->
              cmem:updateClient(CMEM, ClientPID, SendNNr, ?SERVER_LOGGING_FILE,sendmsg)
          end,
          NewCMEM = sendMessages(ClientPID, _CMEM, HBQname, HBQnode),
          loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit, NewCMEM, INNR, erlang:timestamp());
        {ClientPID, getmsgid} ->
          sendMSGID(ClientPID, INNR),
          NewCMEM = cmem:updateClient(_CMEM, ClientPID, INNR, ?SERVER_LOGGING_FILE),
          loop(Latency, Clientlifetime, Servername, HBQname, HBQnode, DLQlimit, NewCMEM, INNR + 1, erlang:timestamp())
      end;
    false ->
      shutdownRoutine(HBQname, HBQnode)
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




sendMSGID(ClientPID, INNr) ->
  %LastMessageId = cmem:getClientNNr(CMEM,ClientPID),
  ClientPID ! {nid, INNr},
  ok.





dropmessage(HBQname, HBQnode, [NNr, Msg, Tsclientout]) ->

  {HBQname, HBQnode} ! {self(), {request, pushHBQ, [NNr, Msg, Tsclientout]}},
  receive
    {reply, ok} ->
      ok
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(?SERVER_LOGGING_FILE, "dropmessage für Nachricht:" ++ Msg ++ " Fehler")
  end.


