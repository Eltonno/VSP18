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
-export([initHBQandDLQ/2, startHBQ/0]).
-define(QUEUE_LOGGING_FILE, "HB-DLQ" ++ os:getenv("Userdomain") ++".log").



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

  erlang:register(HBQname, self()),

  util:logging(?QUEUE_LOGGING_FILE,
    "Die HBQ wurde unter dem Namen:" ++
      util:to_String(HBQname) ++
      "registriert \n"
  ),

  loop(DlqLimit, HBQname, [], [])
.



loop(DlqLimit, HBQname, HBQ, DLQ) ->
  receive

    {ServerPID, {request, initHBQ}} ->
      {_HBQ, _DLQ} = initHBQandDLQ(DlqLimit, ServerPID),
      util:logging(?QUEUE_LOGGING_FILE,
        "Die HBQ && DLQ wurden Initialisiert, der Inhalt {_HBQ, _DLQ}: " ++
          util:to_String( {_HBQ, _DLQ}) ++
          "\n"
      ),
      loop(DlqLimit, HBQname, _HBQ, _DLQ);
    {ServerPID, {request, pushHBQ, [NNr, Msg, TSclientout]}} ->
      _NewHBQ = pushHBQ(ServerPID, HBQ, [NNr, Msg, TSclientout]),
      {NewHBQ, NewDLQ} = pushSeries(_NewHBQ, DLQ),
      loop(DlqLimit, HBQname, NewHBQ, NewDLQ);
    {ServerPID, {request, deliverMSG, NNr, ToClient}} ->
      dlq:deliverMSG(NNr, ToClient, DLQ, ?QUEUE_LOGGING_FILE),
      deliverMSG(ServerPID, DLQ, NNr, ToClient),
      loop(DlqLimit, HBQname, HBQ, DLQ);
    {ServerPID, {request, dellHBQ}} ->
      erlang:unregister(HBQname),
      dlq:delDLQ(DLQ),
      ServerPID ! {reply, ok}
  end.



initHBQandDLQ(Size, ServerPID) ->
  DLQ = dlq:initDLQ(Size, ?QUEUE_LOGGING_FILE),
  ServerPID ! {reply, ok},
  {[], DLQ}.




pushHBQ(ServerPID, OldHBQ, [NNr, Msg, TSclientout]) ->
  Tshbqin = erlang:timestamp(),
  SortedHBQ = sortHBQ(OldHBQ ++ [{NNr, Msg, TSclientout, Tshbqin}]),
  ServerPID ! {reply, ok},
  SortedHBQ.


deliverMSG(ServerPID, DLQ, NNr, ToClient) ->
  {reply, [MSGNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], Terminated} = dlq:deliverMSG(NNr, ToClient, DLQ, ?QUEUE_LOGGING_FILE),
  % ToClient ! {reply, [MSGNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], Terminated},
  ServerPID ! {reply, MSGNr}.

pushSeries(HBQ, {Queue, Size}) ->

  ExpectedMessageNumber = dlq:expectedNrDLQ(dlq:sortDLQ({Queue, Size})),

  {CurrentLastMessageNumber, Msg, TSclientout, TShbqin} = head(HBQ),

  {NHBQ, NDLQ} = case {ExpectedMessageNumber == CurrentLastMessageNumber, two_thirds_reached(HBQ, Size)} of
                   {true, _} ->
                     util:logging(?QUEUE_LOGGING_FILE, 'hier wird push2DLQ ausgeführt true,true im tupel \n'),
                     NewDLQ = dlq:push2DLQ({CurrentLastMessageNumber, Msg, TSclientout, TShbqin}, {Size, Queue}, ?QUEUE_LOGGING_FILE),
                     NewHBQ = lists:filter(fun({Nr, _, _, _}) -> Nr =/= CurrentLastMessageNumber end, HBQ),
                     {NewHBQ, NewDLQ};
                   {false, false} ->
                     util:logging(?QUEUE_LOGGING_FILE, 'hier wird nur zurückgegeben false,false im tupel \n'),
                     {HBQ, {Size, Queue}};
                   {false, true} ->
                     util:logging(?QUEUE_LOGGING_FILE, 'hier wird consistent block false,true im tupel \n'),
                     {ConsistentBlock, NewHBQ} = create_consistent_block(HBQ),
                     {NewHBQ, push_consisten_block_to_dlq(ConsistentBlock, {Size, Queue})}
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
  lists:usort(ORDER, Queue).

