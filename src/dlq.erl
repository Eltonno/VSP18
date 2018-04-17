%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:46
%%%-------------------------------------------------------------------
-module(dlq).
-export([initDLQ/2, delDLQ/1, expectedNr/1, push2DLQ/3, deliverMSG/4]).

%-author("Elton").

%% API
%-export([initDLQ/2]).

%initDLQ(Size,Datei) ->
%  [],
%  receive
%    {request,deliverMSG,NNr,ToClient} ->
%      deliverMSG(NNr,ToClient,Queue,dlq.log);
 %   {request,delDLQ} ->
  %    delDLQ(Queue);
   % {request,push2DLQ} ->
    %  push2DLQ()
%  end.

%delDLQ(Queue) ->
 % io:format("exterminate").

%expectedNr(Queue) ->
 % io:format("number").

%push2DLQ([NNr,Msg,TSclientout,TShbqin],Queue,Datei) ->
 %%%%  {Size, Queue};
    %false ->
    %  util:logging(?QUEUE_LOGGING_FILE, 'FALSE in push2DLQ \n'),
     %%util:logging(DEBUGGER),
      %{Size, Queue ++ [{NNr, Msg, TSclientout,TShbqin, erlang:timestamp()}]}

%  end.
%.

%deliverMSG(MSGNr,ClientPID,Queue,Datei) ->
 % io:format("deliver").

initDLQ(Size, Datei) ->
  util:logging(Datei, lists:concat(["DLQ>>> initialized with capacity: ", Size, "\n"])),
  [[], Size].

%% Löschen der DLQ
delDLQ(_) -> ok.

%% liefert die Nachrichtennummer, die als nächstes in der DLQ gespeichert werden kann. Bei leerer DLQ ist dies 1.
expectedNr([[], _Size]) -> 1;
expectedNr([[[NNr, _Msg, _TSclientout, _TShbqin, _TSdlqin] | _Rest], _Size]) -> NNr + 1.

%% speichert die Nachricht [NNr,Msg,TSclientout,TShbqin] in der DLQ Queue und fügt ihr einen Eingangszeitstempel an
%% (einmal an die Nachricht Msg und als expliziten Zeitstempel TSdlqin mit erlang:now() an die Liste an. Bei Erfolg wird
%% die modifizierte DLQ zurück geliefert. Datei kann für ein logging genutzt werden.
push2DLQ([NNr, Msg, TSclientout, TShbqin], [DLQ, Size], Datei) ->
  if
    length(DLQ) < Size ->
      util:logging(Datei, lists:concat(["DLQ>>> message number ", NNr, " added to DLQ\n"])),
      [[[NNr, Msg, TSclientout, TShbqin, erlang:timestamp()] | DLQ], Size];
    length(DLQ) =:= Size ->
      [LastNNr, _Msg, _TSclientout, _TShbqin, _TSdlqin] = lists:last(DLQ),
      util:logging(Datei, lists:concat(["DLQ>>> message number ", LastNNr, " dropped from DLQ\n"])),
      util:logging(Datei, lists:concat(["DLQ>>> message number ", NNr, " added to DLQ\n"])),
      [[[NNr, Msg, TSclientout, TShbqin, erlang:timestamp()] | lists:droplast(DLQ)], Size]
  end.

%% Sendet eine Nachricht an ClientPID
sendMessage(ClientPID, Message, Terminated) ->
  ClientPID ! {reply, Message, Terminated}.

%% Nachricht wurde nicht gefunden -> nnr ist zu hoch oder DLQ leer, verschicke dummy Nachricht
findMessageToDeliver(_MSGNr, []) ->
  [-1, "No new messages", -1, -1, -1];
%% Nachricht oder nächst höhere Nachricht wurde gefunden und wird returned
findMessageToDeliver(MSGNr, [[NNr, Msg, TSclientout, TShbqin, TSdlqin] | _DLQRest]) when NNr >= MSGNr ->
  [NNr, Msg, TSclientout, TShbqin, TSdlqin];
%% Rekursionsschritt, suche den rest der liste ab
findMessageToDeliver(MSGNr, [[NNr, _Msg, _TSclientout, _TShbqin, _TSdlqin] | DLQRest]) when NNr < MSGNr ->
  findMessageToDeliver(MSGNr, DLQRest).

%% Ausliefern einer Nachricht an einen Leser-Client. Die neuste Nachricht ist links.
%% Es wird die Nachricht ausgeliefert, die von hinten als erstes größer gleich der MSGNr ist.
%% Dadurch wird entweder genau die MSGNr ausgeliefert oder die nächst höchste, da die DLQ sortiert ist.
deliverMSG(MSGNr, ClientPID, [Queue, Size], Datei) ->
  [NNr, Msg, TSclientout, TShbqin, TSdlqin] = findMessageToDeliver(MSGNr, lists:reverse(Queue)),
  Terminated = (expectedNr([Queue, Size]) - 1 =:= NNr) or (NNr =:= -1),
  sendMessage(ClientPID, [NNr, Msg, TSclientout, TShbqin, TSdlqin, erlang:timestamp()], Terminated),
  util:logging(Datei, lists:concat(["DLQ>>> message ", NNr, " sent to Client ", pid_to_list(ClientPID), "\n"])),
  NNr.