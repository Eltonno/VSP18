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
  {[], RemTime}.

delCMEM(_CMEM) ->
  ok.

updateClient({CMEM, RemTime}, ClientID, NNr, Datei) ->
  ClientTS = vsutil:getUTC(),
  util:logging(Datei, lists:concat(["CMEM>>> Client ", pid_to_list(ClientID), " updated (", NNr, "/", ClientTS, ")\n"])),
  {lists:keystore(ClientID, 1, CMEM, {ClientID, NNr, ClientTS}), RemTime}.


%% Request which NNr the client may obtain next
getClientNNr({CMEMList, RemTime}, ClientID) ->
  Existent = lists:keymember(ClientID, 1, CMEMList),
  getClientNNr({CMEMList, RemTime}, ClientID, Existent).

%% unknown Client
getClientNNr(_CMEM, _ClientID, false) -> 1;

%% known client, time exceeded? YES -> 1, NO, NNr + 1
getClientNNr({CMEMList, RemTime}, ClientID, true) ->
  {ClientID, NNr, ClientTimestamp} = lists:keyfind(ClientID, 1, CMEMList),
  util:logging('cmem.log', "\n" ++ util:to_String(CMEMList) ++ "\n" ++ util:to_String(NNr) ++ "\n"),
  NNr + 1.
%%TODO: Hier muss noch wieder die Vergesslichkeit integriert werden.
%%  Duration = ClientTimestamp + RemTime,
%%  Now = vsutil:getUTC(),
%%  Comparisson = vsutil:compareUTC(Duration, Now),
%%  if
%%   Comparisson == afterw -> NNr + 1;
%%    true -> 1
%%  end.