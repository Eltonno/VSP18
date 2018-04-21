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
-define(QUEUE_LOGGING_FILE, "HB-DLQ_" ++ atom_to_list(erlang:node()) ++".log").



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
      {NewHBQ, NewDLQ} = pushHBQ(ServerPID, HBQ, [NNr, Msg, TSclientout], DLQ, DlqLimit),
      %%{NewHBQ, NewDLQ} = pushSeries(_NewHBQ, DLQ, DlqLimit),
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





pushHBQ(ServerPID, OldHBQ, [NNr, Msg, TSclientout], DLQ, DlqLimit) ->
  Tshbqin = erlang:timestamp(),
  DlqNNr = dlq:expectedNr(DLQ),
  if
    NNr >= DlqNNr ->
      SortedHBQ = sortHBQ(OldHBQ ++ [{NNr, Msg, TSclientout, Tshbqin}]),
      ServerPID ! {reply, ok},
      {CNNr, CMsg, CTsclientout, CTshbqin} = head(SortedHBQ),
      TTR = two_thirds_reached(SortedHBQ, DlqLimit),
      if
        CNNr == DlqNNr ->
          NewDlq = dlq:push2DLQ([CNNr, CMsg, CTsclientout, CTshbqin], DLQ, ?QUEUE_LOGGING_FILE),
          [_|HbqRest] = SortedHBQ,
          {HbqRest, NewDlq};
        TTR ->
          NewDlq = dlq:push2DLQ([CNNr-1, "***Fehlernachricht fuer Nachrichten " ++ util:to_String(DlqNNr) ++ " bis " ++ util:to_String(CNNr-1) ++ " um " ++ util:to_String(erlang:timestamp()) ++ "|.", {0,0,0}, {0,0,0}], DLQ, ?QUEUE_LOGGING_FILE),
          {SortedHBQ, NewDlq};
        true ->
          {SortedHBQ, DLQ}
      end;
    true ->
      util:logging(list_to_atom(?QUEUE_LOGGING_FILE), "Die erhaltene Nachrichtennummer ist zu klein, weshalb die Nachricht verworfen wurde."),
      {OldHBQ, DLQ}
  end.

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

