%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:45
%%%-------------------------------------------------------------------
-module(hbq).
-author("Elton").
-export([startHBQ/0,loop/3]).
-define(QUEUE_LOGGING_FILE, "HB-DLQ_" ++ erlang:node() ++".log").



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DLQ Datentyp
%
% {[{NNr, Msg, TSclientout, TShbqin}}, ...]}
% {[Int, String, {Int, Int, Int}, {Int, Int, Int}}, ...]}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


startHBQ() ->
  {ok, ConfigListe} = file:consult('server.cfg'),
  {ok, HBQname} = vsutil:get_config_value(hbqname, ConfigListe),
  {ok, DlqLimit} = vsutil:get_config_value(dlqlimit, ConfigListe),

  HBQPID = spawn(?MODULE, loop, [DlqLimit, [], []]),
  erlang:register(HBQname, HBQPID).

loop(DlqLimit, HBQ, DLQ) ->
  receive
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    {ServerPID, {request, initHBQ}} ->
      ServerPID ! {reply,ok},   %%TODO: Hier muss noch dringend das Problem behoben werden.
                                %%TODO: Einzige Frage ist was wirklich wie zurückgegeben werden muss
      loop(DlqLimit, [], dlq:initDLQ(DlqLimit, ?QUEUE_LOGGING_FILE));
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    {ServerPID, {request, pushHBQ, [NNr, Msg, TSclientout]}} ->
      _NewHBQ = pushHBQ(ServerPID, HBQ, [NNr, Msg, TSclientout]),
      {NewHBQ, NewDLQ} = pushSeries(_NewHBQ, DLQ, DlqLimit),
      loop(DlqLimit, NewHBQ, NewDLQ);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    {ServerPID, {request, deliverMSG, NNr, ToClient}} ->
      SendNNr = dlq:deliverMSG(NNr, ToClient, DLQ, ?QUEUE_LOGGING_FILE),
      util:logging(?QUEUE_LOGGING_FILE, util:to_String(SendNNr)),
      ServerPID !  {reply, SendNNr},
      loop(DlqLimit, HBQ, DLQ);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    {ServerPID, {request, dellHBQ}} ->
      dlq:delDLQ(DLQ),
      ServerPID ! {reply, ok},
      ok
  end.





pushHBQ(ServerPID, OldHBQ, [NNr, Msg, TSclientout]) ->
  Tshbqin = erlang:timestamp(),
  SortedHBQ = sortHBQ(OldHBQ ++ [{NNr, Msg, TSclientout, Tshbqin}]),
  ServerPID ! {reply, ok},
  SortedHBQ.

pushSeries(HBQ, DLQ, Size) ->

  ExpNNr = dlq:expectedNr(DLQ),

  {CurrentLastMessageNumber, Msg, TSclientout, TShbqin} = head(HBQ),

  {NHBQ, NDLQ} = case {ExpNNr == CurrentLastMessageNumber, two_thirds_reached(HBQ, Size)} of
                   {true, _} ->
                     NewDLQ = dlq:push2DLQ([CurrentLastMessageNumber, Msg, TSclientout, TShbqin], DLQ, ?QUEUE_LOGGING_FILE),
                     NewHBQ = lists:filter(fun({Nr, _, _, _}) -> Nr =/= CurrentLastMessageNumber end, HBQ),
                     {NewHBQ, NewDLQ};
                   {false, false} ->
                     {HBQ, DLQ};
                   {false, true} ->
                     {ConsistentBlock, NewHBQ} = create_consistent_block(HBQ),
                     {NewHBQ, push_consisten_block_to_dlq(ConsistentBlock, DLQ)}
                 end,
  {NHBQ, NDLQ}.



push_consisten_block_to_dlq(ConsistentBlock, DLQ) ->
  push_consisten_block_to_dlq_(ConsistentBlock, DLQ).

push_consisten_block_to_dlq_([H | T], DLQ) ->
  NewDLQ = dlq:push2DLQ(H, DLQ, ?QUEUE_LOGGING_FILE),
  push_consisten_block_to_dlq_(T, NewDLQ);

push_consisten_block_to_dlq_([], DLQ) ->
  DLQ.




create_consistent_block([H | T]) ->
  TAIL = erlang:tl(H ++ T),
  create_consistent_block_(H ++ T, TAIL, [], 0);
create_consistent_block([]) ->
  util:logging("create_consistent_block wurde mit einer Leeren HBQ aufgerufen, WTF"),
  {[], []}.

produce_failure_message(NNr, _NNr) ->
  {_NNr, "Fehlernachricht von:" ++ NNr ++ " bis" ++ "_NNr", "Error", "Error"}.

create_consistent_block_([H | T], [_H | _T], Accu, Counter) ->
  {NNr, _, _, _} = H,
  {_NNr, _, _, _} = _H,

  case {erlang:abs(NNr - _NNr) > 1, Counter == 1} of
    {true, true} ->
      {Accu ++ H, _H ++ _T};
    {true, false} ->
      NewAccu = Accu ++ produce_failure_message(NNr, _NNr),
      create_consistent_block_(T, _T, NewAccu, Counter + 1);
    {false, true} ->
      create_consistent_block_(T, _T, Accu ++ H, Counter);
    {false, false} ->
      create_consistent_block_(T, _T, Accu ++ H, Counter)
  end;

create_consistent_block_([H | _], [], _, _) ->
  H.


% Helper funktionen fuer die HBQ

head([]) ->
  1;
head(List) ->
  erlang:hd(List).
% pushSeries helper functions
two_thirds_reached(HBQ, Size) ->
  erlang:length(HBQ) >= 2 / 3 * Size.



sortHBQ(Queue) ->
  ORDER = fun({NNr, _, _, _}, {_NNr, _, _, _}) ->
    NNr < _NNr end,
  lists:sort(ORDER, Queue).

