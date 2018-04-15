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
-define(CLIENT_LOGGING_FILE, "CLIENT").
-define(REDAKTEUR_ATOM, redakteur).
-define(LESER_ATOM, leser).
-define(RECHNER_NAME, os:getenv("USERDOMAIN")).





timestamp_to_millis({MegaSecs, Secs, MicroSecs}) ->
  (MegaSecs * 1000000 + Secs) * 1000 + round(MicroSecs / 1000).


is_time_over(0, _) ->
  true;
is_time_over(Start, Lifetime) ->
  (timestamp_to_millis(erlang:timestamp()) - timestamp_to_millis(Start)) >= Lifetime * 1000.



switchRoles(?REDAKTEUR_ATOM) ->
  ?LESER_ATOM;
switchRoles(?LESER_ATOM) ->
  ?REDAKTEUR_ATOM.



fireAction({redakteur, Servername, Servernode}, Interval, Flag) ->
  sendMSG(Servername, Servernode, 0, Interval, Flag);
fireAction({leser, Servername, Servernode}, _, _) ->
  getMSG(Servername, Servernode).


%start()

%% Definition: Startet einen neuen Client-Prozess der Nachrichten an den (laufenden) Server senden kann und Nachrichten abrufen kann.

%pre: keine
%post: Ein neuer Prozess wurde gestartet, der mit dem Server kommunizieren kann
%return: client started als Atom sonst eine sinnvolle Error-Meldung

start() ->
  {Clients, Lifetime, Servername, Servernode, Sendinterval} = readConfig(),
  spawner(Clients, Lifetime, Servername, Servernode, Sendinterval)
.

spawner(0, Lifetime, Servername, Servernode, Sendinterval) ->
  ok;
spawner(Clients, Lifetime, Servername, Servernode, Sendinterval) ->
  init(Lifetime, Servername, Servernode, Sendinterval, list_to_atom(lists:flatten(io_lib:format("CLIENT~B", [Clients])))),
  %spawn(fun() ->loop(Lifetime, Servername, Servernode, Sendinterval, list_to_atom(lists:flatten(io_lib:format("CLIENT~B", [Clients]))))end),
  spawner(Clients-1, Lifetime, Servername, Servernode, Sendinterval).

readConfig() ->
  {ok, Configfile} = file:consult("client.cfg"),

  {ok, Clients} = vsutil:get_config_value(clients, Configfile),
  {ok, Lifetime} = vsutil:get_config_value(lifetime, Configfile),
  {ok, Servername} = vsutil:get_config_value(servername, Configfile),
  {ok, Servernode} = vsutil:get_config_value(servernode, Configfile),
  {ok, Sendinterval} = vsutil:get_config_value(sendeintervall, Configfile),

  {Clients, Lifetime, Servername, Servernode, Sendinterval}.


init(Lifetime, Servername, Servernode, Sendinterval,ClientName) ->
  erlang:register(ClientName,spawn(client,loop(Lifetime,Servername,Servernode,Sendinterval,erlang:timestamp(),0,?REDAKTEUR_ATOM,false),[])),
  util:logging(list_to_atom(lists:flatten(io_lib:format("~B@~B", [?CLIENT_LOGGING_FILE, ?RECHNER_NAME]))), "Der Client:" ++
    util:to_String(ClientName) ++ " wurde registriert. ~n")
.

%loop(Lifetime, Servername, Servernode, Sendinterval, ClientName) ->
  % registriere den Prozess mit dem Erlang Prozess
%
%  erlang:register(ClientName, self()),
%
%  util:logging(?CLIENT_LOGGING_FILE, "Der Client:" ++
%    util:to_String(ClientName) ++ " wurde registriert. /n"),
%
%
%  loop(Lifetime, Servername, Servernode, Sendinterval, erlang:timestamp(), 0, ?REDAKTEUR_ATOM, false).



loop(Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber, Role, INNRflag) ->

  case not is_time_over(StartTime, Lifetime) of
    true ->
      if TransmittedNumber == 4 ->
        NewRole = switchRoles(Role),
        util:logging(list_to_atom(lists:flatten(io_lib:format("~B@~B", [?CLIENT_LOGGING_FILE, ?RECHNER_NAME]))),
          "Client has switched role from:" ++
            util:to_String(Role) ++
            "| To NewRole:" ++
            util:to_String(NewRole)
            ++ "\n"),
        NewInterval = changeSendInterval(Sendinterval),
        util:logging(?CLIENT_LOGGING_FILE,
          "New Sendinterval is been created From:" ++
            util:to_String(Sendinterval) ++
            "| To NewRole:" ++
            util:to_String(NewInterval)
            ++ "\n"),
        loop(Lifetime, Servername, Servernode, NewInterval, StartTime, 0, NewRole, false);
        true ->
          util:logging(?CLIENT_LOGGING_FILE,
            "Client is before fired Action for Role of:" ++
              util:to_String(Role) ++ "\n"),
          ActionReturn = fireAction({Role, Servername, Servernode}, Sendinterval, INNRflag),
          util:logging(?CLIENT_LOGGING_FILE,
            "Client is fired Action for Role of:" ++
              util:to_String(Role) ++
              "| With ActionReturn:" ++
              util:to_String(ActionReturn)
              ++ "\n"),
          case erlang:is_tuple(ActionReturn) of
            true ->
              loop(Lifetime, Servername, Servernode, Sendinterval, StartTime, TransmittedNumber + 1, Role, INNRflag);
            false ->
              loop(Lifetime, Servername, Servernode, Sendinterval, StartTime, 0, switchRoles(Role), false)
          end
      end;
    false ->
      util:logging(?CLIENT_LOGGING_FILE, "ClientID-X Lifetime is over - terminating at" ++ util:to_String(erlang:timestamp()) ++ "\n"),
      erlang:exit("Lifetime is over")
  end.





changeSendInterval(Sendinterval) ->
  util:logging(?CLIENT_LOGGING_FILE, "Trying to change Sendinterval for:" ++ util:to_String(Sendinterval) ++ "\n"),

  Prob = rand:uniform(),
  if
    (Sendinterval * (Prob + 0.5)) > 2 ->
      (Sendinterval * (Prob + 0.5));
    true ->
      2
  end.



logIncomeMsg([NNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], TimeStampClIn) ->
  NewMessage = util:to_String(NNr) ++
    "te_Nachricht. C Out:" ++
    util:to_String(TSclientout) ++
    "| ; HBQ In:" ++
    util:to_String(TShbqin) ++
    "| ; DLQ In:" ++
    util:to_String(TSdlqin) ++
    "| ; DLQ Out:" ++
    util:to_String(TSdlqout) ++
    "| ; C In:" ++
    util:to_String(TimeStampClIn) ++
    "| Nachricht:" ++
    util:to_String(Msg) ++
    "\n",
  util:logging(?CLIENT_LOGGING_FILE, NewMessage).



getMSG(Servername, Servernode) ->
  {Servername, Servernode} ! {self(), getmessages},

  util:logging(?CLIENT_LOGGING_FILE, "Client send getmessages  \n"),
  receive
    {reply, [NNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], true} ->
      logIncomeMsg([NNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], erlang:timestamp()),
      util:logging(?CLIENT_LOGGING_FILE, "Client get message NR:" ++
        util:to_String(NNr) ++
        "with an repeat flag: true" ++
        "\n"),
      getMSG(Servername, Servernode);
    {reply, [NNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], false} ->
      util:logging(?CLIENT_LOGGING_FILE, "Client get message NR:" ++
        util:to_String(NNr) ++
        "with an repeat flag: false" ++
        "\n"),
      logIncomeMsg([NNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], erlang:timestamp()),
      ok
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(?CLIENT_LOGGING_FILE, "Leser did not response" ++ util:to_String(erlang:timestamp()))
  end.


askForMSGID(Servername, Servernode) ->
  {Servername, Servernode} ! {self(), getmsgid},
  util:logging(?CLIENT_LOGGING_FILE, "Client send getmsgid  \n"),
  receive
    {nid, Number} ->
      util:logging(?CLIENT_LOGGING_FILE, "Client received in getmsgid an nid: " ++ util:to_String(Number) ++ "\n"),
      Number
  after ?MAXIMAL_RESPONSE_TIME_BEFORE_ERROR ->
    util:logging(?CLIENT_LOGGING_FILE, "getMSG did not received response frome Server at" ++ util:to_String(erlang:timestamp()))
  end.



sendMSG(Servername, Servernode, TimeLastSending, Interval, INNRflag) ->


  Msg = "Gruppe:" ++
    util:to_String(?GRUPPE) ++
    "; | Team:" ++
    util:to_String(?TEAM) ++
    "; | Rechnername:" ++
    util:to_String(?RECHNER_NAME),
  INNr = askForMSGID(Servername, Servernode),
  timer:sleep(trunc(Interval * 1000)),
  TSClientout = erlang:timestamp(),
  {Servername, Servernode} ! {dropmessage, [INNr, Msg, TSClientout]},
  util:logging(?CLIENT_LOGGING_FILE, "Client send dropmessage with Message: " ++ util:to_String([INNr, Msg, TSClientout]) ++ " .\n"),
  TSClientout.