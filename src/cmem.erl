%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:45
%%%-------------------------------------------------------------------
-module(cmem).
-author("Elton").
-export([initCMEM/2, getClientNNr/2, updateClient/4, delExpiredCl/1]).








% initCMEM(RemTime, Datei)

%% Definition: Initialisiert die CMEM für den Server.

% pre: keine
% post: neues 2-Tupel erstellt
% return: {RemTime, []} - 2-Tupel mit RemTime als erstes Element und eine leere CMEM-Liste als 2. Element

initCMEM(RemTime, Datei) ->
  {RemTime, []},
NewMessage = "CMEM initialisiert\n",
util:logging(Datei, NewMessage).


% updateClient(CMEM, ClientID, NNr, Datei)

%% Definition: Speichert/Aktualisiert im CMEM die ClientID mit der NNr.

%pre: nötige Übergabeparameter sind korrekt
%post: neuer Client gespeichert, oder einen bereits vorhandenen Client aktualisiert
%% return: aktualisiertes CMEM


%% {Clientlifetime,CMEM} {Int,[{<PID>,Int,{Int,Int,Int}}]}
%% Clientlifetime,CMEM} {Size,[{ClientPID,LastMessageID,LastMessageTimestamp}]}




updateClient({Clientlifetime,CMEM}, ClientID, NNr, Datei) ->

%%%%%%Überprüfen ob dieser Client schon in der CMEM ist
  {CClientID,LLastMessageNumber,TTime} =

  case lists:keyfind(ClientID,1,CMEM) of
    %%%%%%Wenn ja, NNr aktualisieren

    {ClientID,LastMessageNumber,Time} ->
        {ClientID,LastMessageNumber,Time};
      false ->
        {ClientID,NNr,erlang:timestamp()}
   end,
Filter = fun({_ClientID,_LastMessageNumer, _Time}) -> _ClientID =/= ClientID end,

  _NewCMEM = lists:filter(Filter,CMEM),
  %%%%Ansonsten Client mit NNr in CMEM speichern

  {Clientlifetime,_NewCMEM ++ [{ClientID,LLastMessageNumber,erlang:now()}]},

  %%%%%Loggen

NewMessage = util:to_String(ClientID) ++
" hat Nachricht " ++
util:to_String(util:to_String/1(NNr)) ++
" bekommen und der CMEM wurde aktualisiert " ++
"\n",
util:logging(Datei, NewMessage).





%%  F = fun({_ClientID,_LastMessageNumer, _Time}) -> _ClientID =/= ClientID end,
%%  _NewCMEM = lists:filter(F,CMEM),
%%  {Clientlifetime,_NewCMEM ++ [{ClientID,NNr,erlang:timestamp()}]};
%%
%%updateClient({Clientlifetime,CMEM}, ClientID, NNr, Datei) ->
%%  %Find = fun({_ClientID,_LastMessageNumer, _Time}) -> _ClientID == ClientID end,
%%
%%  Filter = fun({_ClientID,_LastMessageNumer, _Time}) -> _ClientID =/= ClientID end,
%%  {CClientID,LLastMessageNumber,TTime} =
%%    case lists:keyfind(ClientID,1,CMEM) of
%%      {ClientID,LastMessageNumber,Time} ->
%%        {ClientID,LastMessageNumber,Time};
%%      false ->
%%        {ClientID,NNr,erlang:timestamp()}
%%    end,
%%
%%
%%  _NewCMEM = lists:filter(Filter,CMEM),
%%
%%  {Clientlifetime,_NewCMEM ++ [{ClientID,LLastMessageNumber,erlang:now()}]}.


% getClientNNr(CMEM, ClientID)

%% Definition: Liefert dem Server die nächste Nachrichtennummer die an die ClientID geschickt werden soll.

% pre: keine
% post: nicht veränderte CMEM, da nur lesend
% return: ClientID als Integer-Wert, wenn nicht vorhanden wird 1 zurückgegeben

getClientNNr(CMEM, ClientID) ->
  get_last_message_id(ClientID, CMEM).


get_last_message_id(_, []) ->
  1;

get_last_message_id(ClientID, CMEM) ->
  {ClientID, Last_message_id, _Time} = lists:keyfind(ClientID, 1, CMEM),
  Last_message_id.


% delExpiredCl(CMEM, Clientlifetime)

%%Definition: In dieser Methode werden die Clients gelöscht, welche die Clientlifetime überschritten haben.

%pre: keine
%post: veränderte CMEM
%return: Das Atom ok als Rückgabewert // falsch veränderte CMEM

delExpiredCl({Clientlifetime, Queue}) ->
  Now = timestamp_to_millis(erlang:timestamp()),
  F = fun({_ClientID,_LastMessageNumer, _Time}) -> (Now - timestamp_to_millis(_Time)) < Clientlifetime * 1000   end,
  NewQueue = lists:filter(F,Queue),
  {Clientlifetime,NewQueue}.

timestamp_to_millis({MegaSecs, Secs, MicroSecs}) ->
  (MegaSecs * 1000000 + Secs) * 1000 + round(MicroSecs / 1000).