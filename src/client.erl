%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:45
%%%-------------------------------------------------------------------
-module(client).
-author("Elton").


-export([start/0,loop/9]).


-define(GRUPPE, '3').
-define(TEAM, '02').
-define(MAXIMAL_RESPONSE_TIME_BEFORE_ERROR, 5000).
-define(CLIENT_LOGGING_FILE, 'CLIENT').
-define(REDAKTEUR_ATOM, redakteur).
-define(LESER_ATOM, leser).
-define(RECHNER_NAME, erlang:node()).





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

fireAction({redakteur, Servername, Servernode}, Interval, ClientName, OwnMsgs) ->
  dropMSG(Servername, Servernode, Interval, ClientName, OwnMsgs);
fireAction({leser, Servername, Servernode}, _, ClientName, OwnMsgs) ->
  getMSG(Servername, Servernode, ClientName, OwnMsgs).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start() ->
  {Clients, Lifetime, Servername, Servernode, Sendinterval} = readConfig(),
  spawner(Clients, Lifetime, Servername, Servernode, Sendinterval).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

spawner(0, _Lifetime, _Servername, _Servernode, _Sendinterval) ->
  ok;
spawner(Clients, Lifetime, Servername, Servernode, Sendinterval) ->
%%  ClientPID = spawn(?MODULE, loop, [("Client" ++ util:to_String(Clients)), Lifetime, Servername, Servernode, Sendinterval, erlang:timestamp(), 0, ?REDAKTEUR_ATOM, [] ]),
  register("Client_" ++ util:to_String(Clients), spawn(?MODULE, loop, [("Client" ++ util:to_String(Clients)), Lifetime, Servername, Servernode, Sendinterval, erlang:timestamp(), 0, ?REDAKTEUR_ATOM, [] ])),
  util:logging(list_to_atom(("Client_" ++ util:to_String(Clients)) ++ "@" ++ atom_to_list(?RECHNER_NAME) ++ ".log"), "Der Client:" ++
    util:to_String(("Client_" ++ util:to_String(Clients))) ++ " wurde registriert. ~n"),
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

forgottenMessage(NNr, Timestamp, ClientName) ->
  util:logging(list_to_atom(ClientName ++ "@" ++ ?RECHNER_NAME ++ ".log"), util:to_String(NNr) ++ "te_Nachricht um " ++ io:format("~s~n",[print_time:format_utc_timestamp(Timestamp)]) ++ " wurde vergessen.\n").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

loop(ClientName, Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber, Role, OwnMsgs) ->

  case not is_time_over(StartTime, Lifetime) of
    true ->
      if
        TransmittedNumber == 5 ->
          NNr = getMSGID(Servername, Servernode),
          forgottenMessage(NNr, calendar:now_to_local_time(erlang:timestamp()), ClientName),
          loop(ClientName, Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber + 1, Role, OwnMsgs);
        TransmittedNumber == 6 ->
          NewRole = switchRoles(Role),
          NewInterval = changeSendInterval(Sendinterval),
          loop(ClientName, Lifetime, Servername, Servernode, NewInterval, StartTime, 0, NewRole, OwnMsgs);
        true ->
          ActionReturn = fireAction({Role, Servername, Servernode}, Sendinterval, ClientName, OwnMsgs),
          case erlang:is_tuple(ActionReturn) of
            true ->
              loop(ClientName, Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber + 1, Role, OwnMsgs);
            false ->
              loop(ClientName, Lifetime, Servername, Servernode, Sendinterval, StartTime, 0, switchRoles(Role), OwnMsgs)
          end
      end;
    false ->
      util:logging(list_to_atom(ClientName ++ "@" ++ ?RECHNER_NAME ++ ".log"), util:to_String(ClientName) ++ " exceeded it's lifetime at " ++ util:to_String(erlang:timestamp()) ++ "\n"),
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

readerLOG([NNr, Msg, TSclientout, TShbqin, TSdlqout], ClientName, OwnMsgs) ->
  TSclientin = calendar:now_to_local_time(erlang:timestamp()),
  if
    TSclientout == {0,0,0} ->     %% vsutil:equalTS(TSclientout, {0,0,0}) musn't be used in guard therefor we used <---
      util:logging(list_to_atom(ClientName ++ "@" ++ atom_to_list(?RECHNER_NAME) ++ ".log"), Msg++ "| C In: " ++ util:to_String(TSclientin) ++"\n");
    true ->
      Boolean = vsutil:lessTS(TSdlqout, TSclientin),
      Member = lists:member(NNr, OwnMsgs),
      %%util:logging(list_to_atom(ClientName ++ "@" ++ atom_to_list(?RECHNER_NAME) ++ ".log"),util:to_String(Member)),
      %%case Member of
        %%true->
%%          if
%%            Boolean ->
%%              util:logging(list_to_atom(ClientName ++ "@" ++ ?RECHNER_NAME ++ ".log"),
%%                util:to_String(NNr) ++
%%                  "te_Nachricht. C Out:" ++
%%                  util:to_String(TSclientout) ++
%%                  "| ; HBQ In:" ++
%%                  util:to_String(TShbqin) ++
%%                  "| ; DLQ Out:" ++
%%                  util:to_String(TSdlqout) ++
%%                  "|***Nachricht aus der Zukunft ^^ *******\n");
%%            true ->
%%              util:logging(list_to_atom(ClientName ++ "@" ++ ?RECHNER_NAME ++ ".log"),
%%                util:to_String(NNr) ++
%%                  "te_Nachricht. C Out:" ++
%%                  util:to_String(TSclientout) ++
%%                  "| ; HBQ In:" ++
%%                  util:to_String(TShbqin) ++
%%                  "| ; DLQ Out:" ++
%%                  util:to_String(TSdlqout) ++
%%                  "*******\n")
%%          end;
%%        false ->
%%          Boolean = vsutil:lessTS(TSdlqout, TSclientin),
          if
            Boolean ->
              util:logging(list_to_atom(ClientName ++ "@" ++ ?RECHNER_NAME ++ ".log"),
                util:to_String(NNr) ++
                  "te_Nachricht. C Out:" ++
                  util:to_String(TSclientout) ++
                  "| ; HBQ In:" ++
                  util:to_String(TShbqin) ++
                  "| ; DLQ Out:" ++
                  util:to_String(TSdlqout) ++
                  "|***Nachricht aus der Zukunft ^^\n");
            true ->
              util:logging(list_to_atom(ClientName ++ "@" ++ atom_to_list(?RECHNER_NAME) ++ ".log"),
                util:to_String(NNr) ++
                  "te_Nachricht. C Out:" ++
                  util:to_String(TSclientout) ++
                  "| ; HBQ In:" ++
                  util:to_String(TShbqin) ++
                  "| ; DLQ Out:" ++
                  util:to_String(TSdlqout) ++
                  "\n")
          end
      end,
 %% end,
  ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

getMSG(Servername, Servernode, ClientName, OwnMsgs) ->
  {Servername, Servernode} ! {self(), getmessages},
  receive
    {reply, [NNr, Msg, TSclientout, TShbqin, _TSdlqin, TSdlqout], false} ->
      readerLOG([NNr, Msg, TSclientout, TShbqin, TSdlqout], ClientName, OwnMsgs),
      getMSG(Servername, Servernode, ClientName, OwnMsgs);
    {reply, [NNr, Msg, TSclientout, TShbqin, _TSdlqin, TSdlqout], true} ->
      readerLOG([NNr, Msg, TSclientout, TShbqin, TSdlqout], ClientName, OwnMsgs),
      ok
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

getMSGID(Servername, Servernode) ->
  {Servername, Servernode} ! {self(), getmsgid},
  receive
    {nid, Number} ->
      Number
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

dropMSG(Servername, Servernode, Interval, ClientName, OwnMsgs) ->
  Msg = "Gruppe:" ++
    util:to_String(?GRUPPE) ++
    "; | Team:" ++
    util:to_String(?TEAM) ++
    "; | Rechnername:" ++
    util:to_String(?RECHNER_NAME),
  INNr = getMSGID(Servername, Servernode),
   NewOwn = OwnMsgs ++ INNr,
  timer:sleep(trunc(Interval * 1000)),
  TSClientout = erlang:timestamp(),
  {Servername, Servernode} ! {dropmessage, [INNr, Msg, TSClientout]},
  util:logging(list_to_atom(ClientName ++ "_" ++ atom_to_list(?RECHNER_NAME) ++ ".log"), util:to_String(INNr) ++ "te_Nachricht. C Out: " ++ util:to_String(calendar:now_to_local_time(TSClientout)) ++ ". | gesendet\n"),
  NewOwn.