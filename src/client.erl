%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:44
%%%-------------------------------------------------------------------
-module(client).
-author("Elton").


-export([start/0]).


-define(GRUPPE, '3').
-define(TEAM, '02').
-define(MAXIMAL_RESPONSE_TIME_BEFORE_ERROR, 5000).
-define(CLIENT_LOGGING_FILE, 'CLIENT').
-define(REDAKTEUR_ATOM, redakteur).
-define(LESER_ATOM, leser).
-define(RECHNER_NAME, os:getenv("USERDOMAIN")).





timestamp_to_millis({MegaSecs, Secs, MicroSecs}) ->
  (MegaSecs * 1000000 + Secs) * 1000 + round(MicroSecs / 1000).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

is_time_over(0, _) ->
  true;
is_time_over(Start, Lifetime) ->
  (timestamp_to_millis(erlang:timestamp()) - timestamp_to_millis(Start)) >= Lifetime * 1000.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

switchRoles(?REDAKTEUR_ATOM) ->
  ?LESER_ATOM;
switchRoles(?LESER_ATOM) ->
  ?REDAKTEUR_ATOM.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fireAction({redakteur, Servername, Servernode}, Interval, Flag, ClientName, CID) ->
  dropMSG(Servername, Servernode, 0, Interval, Flag, ClientName, CID);
fireAction({leser, Servername, Servernode}, _, _, ClientName, CID) ->
  getMSG(Servername, Servernode, ClientName, CID).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start() ->
  {Clients, Lifetime, Servername, Servernode, Sendinterval} = readConfig(),
  spawner(Clients, Lifetime, Servername, Servernode, Sendinterval).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

spawner(0, _Lifetime, _Servername, _Servernode, _Sendinterval) ->
  ok;
spawner(Clients, Lifetime, Servername, Servernode, Sendinterval) ->
  spawn(fun() -> init(Lifetime, Servername, Servernode, Sendinterval, ("Client" ++ util:to_String(Clients)))end),
  spawner(Clients-1, Lifetime, Servername, Servernode, Sendinterval).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

readConfig() ->
  {ok, Configfile} = file:consult("client.cfg"),
  {ok, Clients} = vsutil:get_config_value(clients, Configfile),
  {ok, Lifetime} = vsutil:get_config_value(lifetime, Configfile),
  {ok, Servername} = vsutil:get_config_value(servername, Configfile),
  {ok, Servernode} = vsutil:get_config_value(servernode, Configfile),
  {ok, Sendinterval} = vsutil:get_config_value(sendeintervall, Configfile),

  {Clients, Lifetime, Servername, Servernode, Sendinterval}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init(Lifetime, Servername, Servernode, Sendinterval,ClientName) ->
  erlang:register(list_to_atom(ClientName),client,loop(ClientName,self(),Lifetime,Servername,Servernode,Sendinterval,erlang:timestamp(),0,?REDAKTEUR_ATOM,false),[]),
  util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"), "Der Client:" ++
    util:to_String(ClientName) ++ " wurde registriert. ~n").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

forgottenMessage(NNr, Timestamp, ClientName) ->
  util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"), util:to_String(NNr) ++ "te_Nachricht um " ++ util:to_String(Timestamp) ++ " wurde vergessen.\n").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

loop(ClientName, CID, Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber, Role, INNRflag) ->

  case not is_time_over(StartTime, Lifetime) of
    true ->
      if
        TransmittedNumber == 5 ->
          NNr = getMSGID(Servername, Servernode, CID),
          forgottenMessage(NNr, calendar:now_to_local_time(erlang:timestamp()), ClientName),
          loop(ClientName, CID, Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber + 1, Role, INNRflag);
        TransmittedNumber == 6 ->
          NewRole = switchRoles(Role),
          NewInterval = changeSendInterval(Sendinterval),
          loop(ClientName, CID, Lifetime, Servername, Servernode, NewInterval, StartTime, 0, NewRole, false);
        true ->
          ActionReturn = fireAction({Role, Servername, Servernode}, Sendinterval, INNRflag, ClientName, CID),
          case erlang:is_tuple(ActionReturn) of
            true ->
              loop(ClientName, CID, Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber + 1, Role, INNRflag);
            false ->
              loop(ClientName, CID, Lifetime, Servername, Servernode, Sendinterval, StartTime, 0, switchRoles(Role), false)
          end
      end;
    false ->
      util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"), "ClientID-X Lifetime is over - terminating at" ++ util:to_String(erlang:timestamp()) ++ "\n"),
      erlang:exit("Lifetime is over")
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

changeSendInterval(Sendinterval) ->
  Prob = rand:uniform(),
  if
    (Sendinterval * (Prob + 0.5)) > 2 ->
      (Sendinterval * (Prob + 0.5));
    true ->
      2
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

readerLOG([NNr, Msg, TSclientout, TShbqin, TSdlqout], ClientName) ->
  TSclientin = calendar:now_to_local_time(erlang:timestamp()),
  if
    TSclientout == {0,0,0} ->     %% vsutil:equalTS(TSclientout, {0,0,0}) musn't be used in guard therefor we used <---
      util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"), Msg++ "| C In: " ++ util:to_String(TSclientin) ++"\n");
    true ->
      Boolean = vsutil:lessTS(TSdlqout, TSclientin),
      if
        Boolean ->
          util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"),
            util:to_String(NNr) ++
            "te_Nachricht. C Out:" ++
            util:to_String(calendar:now_to_local_time(TSclientout)) ++
            "| ; HBQ In:" ++
            util:to_String(calendar:now_to_local_time(TShbqin)) ++
            "| ; DLQ Out:" ++
            util:to_String(calendar:now_to_local_time(TSdlqout)) ++
            "|***Nachricht von Zukunft ^^\n");
        true ->
          util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"),
            util:to_String(NNr) ++
            "te_Nachricht. C Out:" ++
            util:to_String(calendar:now_to_local_time(TSclientout)) ++
            "| ; HBQ In:" ++
            util:to_String(calendar:now_to_local_time(TShbqin)) ++
            "| ; DLQ Out:" ++
            util:to_String(calendar:now_to_local_time(TSdlqout)) ++
            "\n")
      end
  end,
  ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

getMSG(Servername, Servernode, ClientName, CID) ->
  {Servername, Servernode} ! {CID, getmessages},
  receive
    {reply, [NNr, Msg, TSclientout, TShbqin, _TSdlqin, TSdlqout], false} ->
      readerLOG([NNr, Msg, TSclientout, TShbqin, TSdlqout], ClientName),
      getMSG(Servername, Servernode, ClientName, CID);
    {reply, [NNr, Msg, TSclientout, TShbqin, _TSdlqin, TSdlqout], true} ->
      readerLOG([NNr, Msg, TSclientout, TShbqin, TSdlqout], ClientName),
      ok
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"), "Leser did not response" ++ util:to_String(erlang:timestamp()))
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

getMSGID(Servername, Servernode, CID) ->
  {Servername, Servernode} ! {CID, getmsgid},
  receive
    {nid, Number} ->
      Number
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(?CLIENT_LOGGING_FILE, "getMSG did not received response frome Server at" ++ util:to_String(erlang:timestamp()))
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

dropMSG(Servername, Servernode, TimeLastSending, Interval, INNRflag, ClientName, CID) ->
  Msg = "Gruppe:" ++
    util:to_String(?GRUPPE) ++
    "; | Team:" ++
    util:to_String(?TEAM) ++
    "; | Rechnername:" ++
    util:to_String(?RECHNER_NAME),
  INNr = getMSGID(Servername, Servernode, CID),
  timer:sleep(trunc(Interval * 1000)),
  TSClientout = erlang:timestamp(),
  {Servername, Servernode} ! {dropmessage, [INNr, Msg, TSClientout]},
  util:logging(list_to_atom(string:uppercase(ClientName) ++ "@" ++ ?RECHNER_NAME ++ ".log"), util:to_String(INNr) ++ "te_Nachricht. C Out: " ++ util:to_String(calendar:now_to_local_time(TSClientout)) ++ ". | gesendet\n"),
  TSClientout.