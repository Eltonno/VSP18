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
-export([initCMEM/2, getClientNNr/2, updateClient/4, delCMEM/1]).



% initCMEM(RemTime, Datei)
%% Definition: Initialisiert die CMEM für den Server.

initCMEM(RemTime, Datei) ->
  util:logging(Datei, "CMEM initialisiert\nRemTime is: " ++ util:to_String(RemTime) ++ "\n"),
  [RemTime, []].

delCMEM(_CMEM) ->
  ok.


% updateClient(CMEM, ClientID, NNr, Datei)
%% Definition: Speichert/Aktualisiert im CMEM die ClientID mit der NNr.

%% {Clientlifetime,CMEM} {Int,[{<PID>,Int,{Int,Int,Int}}]}
%% Clientlifetime,CMEM} {Size,[{ClientPID,LastMessageID,LastMessageTimestamp}]}




updateClient([RemTime,CMEM], ClientID, NNr, Datei) ->
  ClientTS = vsutil:getUTC(),
  util:logging(Datei, lists:concat(["CMEM>>> Client ", pid_to_list(ClientID), " updated (", NNr, "/", ClientTS, ")\n"])),
  [lists:keystore(ClientID, 1, CMEM, {ClientID, NNr, ClientTS}), RemTime].

%%
%%%%%%%%Überprüfen ob dieser Client schon in der CMEM ist
%%  {CClientID,LLastMessageNumber,TTime} =
%%
%%  case lists:keyfind(ClientID,1,CMEM) of
%%    %%%%%%Wenn ja, NNr aktualisieren
%%
%%    {ClientID,LastMessageNumber,Time} ->
%%        {ClientID,LastMessageNumber,Time};
%%      false ->
%%        {ClientID,NNr,erlang:timestamp()}
%%   end,
%%Filter = fun({_ClientID,_LastMessageNumer, _Time}) -> _ClientID =/= ClientID end,
%%
%%  _NewCMEM = lists:filter(Filter,CMEM),
%%  %%%%Ansonsten Client mit NNr in CMEM speichern
%%
%%  %%%%%Loggen
%%
%%  NewMessage = util:to_String(ClientID) ++
%%    " hat Nachricht " ++
%%    util:to_String(NNr) ++
%%    " bekommen und der CMEM wurde aktualisiert " ++
%%    "\n",
%%  util:logging(Datei, NewMessage),
%%
%%  {_NewCMEM ++ [{ClientID,LLastMessageNumber,erlang:timestamp()}]}.





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
%%  {Clientlifetime,_NewCMEM ++ [{ClientID,LLastMessageNumber,erlang:timestamp()}]}.


% getClientNNr(CMEM, ClientID)

%% Definition: Liefert dem Server die nächste Nachrichtennummer die an die ClientID geschickt werden soll.

% pre: keine
% post: nicht veränderte CMEM, da nur lesend
% return: ClientID als Integer-Wert, wenn nicht vorhanden wird 1 zurückgegeben

%%getClientNNr(CMEM, ClientID) ->
%%  util:logging('CMEM', "\n" ++ util:to_String(CMEM) ++ "\n"),
%%  get_last_message_id(CMEM, ClientID).
%%
%%%% LNNr -> Letzte Nachrichten Nummer
%%
%%get_last_message_id([], _) ->
%%  1;
%%
%%get_last_message_id(CMEM, ClientID) ->
%%%%  {ClientID, LNNr, _Time} = lists:keyfind(ClientID, 1, CMEM),
%%%%  Last_message_id.
%%  NNr = case lists:keyfind(ClientID, 1, CMEM) of
%%          {ClientID, LNNr, _Time} -> {ClientID, LNNr, _Time};
%%          false -> {ClientID, 1, erlang:timestamp()}
%%        end,
%%  NNr.

%% Request which NNr the client may obtain next
getClientNNr([RemTime, CMEM], ClientID) ->
  Existent = lists:keymember(ClientID, 1, CMEM),
  if
    Existent ->
      {ClientID, LNNr, Time} = lists:keyfind(ClientID, 1, CMEM),
      Duration = Time + RemTime,
      Now = vsutil:getUTC(),
      if
        Duration >= Now -> LNNr + 1;
        true -> 1
      end;
    true ->
      1
  end.

