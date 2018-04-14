%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:46
%%%-------------------------------------------------------------------
-module(dlq).
-author("Elton").

%% API
-export([]).

initDLQ(Size,Datei) ->
  Queue = [],
  receive
    {request,deliverMSG,NNr,ToClient} ->
      deliverMSG(NNr,ToClient,Queue,dlq.log);
    {request,delDLQ} ->
      delDLQ(Queue);
    {request,push2DLQ} ->
      push2DLQ()
  end.

delDLQ(Queue) ->
  io:format("exterminate").

expectedNr(Queue) ->
  io:format("number").

push2DLQ([NNr,Msg,TSclientout,TShbqin],Queue,Datei) ->
  io:format("push").

deliverMSG(MSGNr,ClientPID,Queue,Datei) ->
  io:format("deliver").
