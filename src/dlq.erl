%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:45
%%%-------------------------------------------------------------------
-module(dlq).
-export([initDLQ/2, delDLQ/1, expectedNr/1, push2DLQ/3, deliverMSG/4]).

-author("Elton").

initDLQ(Size, Datei) ->
  util:logging(Datei, lists:concat(["DLQ>>> initialized with capacity: ", Size, "\n"])),
  [[], Size].

delDLQ(_) -> ok.

expectedNr([[], _Size]) -> 1;
expectedNr([[[NNr, _Msg, _TSclientout, _TShbqin, _TSdlqin] | _Rest], _Size]) -> NNr + 1.


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

sendMessage(ClientPID, Message, Terminated) ->
  ClientPID ! {reply, Message, Terminated}.

findMessageToDeliver(_MSGNr, []) ->
  [-1, "No new messages", -1, -1, -1];

findMessageToDeliver(MSGNr, [[NNr, Msg, TSclientout, TShbqin, TSdlqin] | _DLQRest]) when NNr >= MSGNr ->
  [NNr, Msg, TSclientout, TShbqin, TSdlqin];

findMessageToDeliver(MSGNr, [[NNr, _Msg, _TSclientout, _TShbqin, _TSdlqin] | DLQRest]) when NNr < MSGNr ->
  findMessageToDeliver(MSGNr, DLQRest).

deliverMSG(MSGNr, ClientPID, [Queue, Size], Datei) ->
  [NNr, Msg, TSclientout, TShbqin, TSdlqin] = findMessageToDeliver(MSGNr, lists:reverse(Queue)),
  Terminated = (expectedNr([Queue, Size]) - 1 =:= NNr) or (NNr =:= -1),
  sendMessage(ClientPID, [NNr, Msg, TSclientout, TShbqin, TSdlqin, erlang:timestamp()], Terminated),
  util:logging(Datei, lists:concat(["DLQ>>> message ", NNr, " sent to Client ", pid_to_list(ClientPID), "\n"])),
  NNr.