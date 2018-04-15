%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. Apr 2018 16:46
%%%-------------------------------------------------------------------
%-module(dlq).
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%-------------------------------------------------------------------
%%% @author kbrusch
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 02. Apr 2015 10:06 AM
%%%-------------------------------------------------------------------
-module(dlq).
-author("kbrusch").
-export([initDLQ/2, deliverMSG/3, sortDLQ/1, expectedNrDLQ/1, push2DLQ/3,last/1]).
-define(QUEUE_LOGGING_FILE, "HBQ.txt").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DLQ Datentyp
%
% {Size, [{NNr, Msg, TSclientout, TShbqin, TSdlqin}, ...]}
% {Int, [{Int, String, {Int,Int, Int} , {Int,Int, Int}, {Int,Int, Int}}, ...]}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% initDLQ(Size, Datei)

% Vom HBQ-Prozess aufgerufene Methode die eine neue leere DLQ-ADT zurückliefert.

% pre: keine
% post: 2-Tupel mit Größenangabe, sowie einer leeren Liste
% return: {Size, []} - 2-Tupel mit Size als 1. Element und einer leeren Liste als 2. Element

initDLQ(Size, Datei) ->
  util:logging('DLQ init', Datei),
  {Size, []}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%delDLQ(Queue) fehlt
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% push2DLQ([NNr, Msg, TSclientout, TShbqin], Queue, Datei)

% Die von dem HBQ-Prozess kommende Nachricht im Format: [NNr, Msg, TSclientout, TShbqin] wird in die DLQ eingefügt.

% pre: Übergabeparameter Queue ist korrekte DLQ-ADT
% post: die DLQ ist nun um eine Nachricht gewachsen, sofern die Größe es zugelassen hat
% return: die neue DLQ: NewDLQ ; wurde die maximale Größe der DLQ erreicht wird eine erkennbare Error-Meldung zurückgegeben


push2DLQ({NNr, Msg, TSclientout, TShbqin}, {Size, Queue}, Datei) ->
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % {Size, Queue}? Müsste eigentlich nur Queue sein
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  util:logging(Datei,"Aufruf von push2DLQ mit {Size, Queue} :" ++
    util:logging(Datei, {Size, Queue}) ++ "\n"),
  util:logging(Datei," erlang:length(Queue) < Size :" ++
    util:logging(Datei, erlang:length(Queue) < Size) ++ "\n"),
  case erlang:length(Queue) >= Size of
    true ->
      util:logging(Datei,"Die DLQ ist Voll, Message:" ++ util:logging(Datei, NNr) ++ " kann nicht verarbeitet werden!"),
      {Size, Queue};
    false ->
      util:logging(Datei, 'FALSE in push2DLQ \n'),
      DEBUGGER = Queue ++ [{NNr, Msg, TSclientout,TShbqin, erlang:timestamp()}],
      util:logging(Datei, DEBUGGER),
      {Size, Queue ++ [{NNr, Msg, TSclientout,TShbqin, erlang:timestamp()}]}

  end.


% deliverMSG(MSGNr, ClientPID, Queue, Datei)

% Der HBQ-Prozess gibt eine MSGNr die an den Client verschickt werden soll
% Die Nachrichten an den Client enthält ob es noch weitere Nachrichten für den Client gibt

% pre: die Queue ist in Form der DLQ-ADT sowie die ClientPID
% post: eine MSGNr wurde zurückgegeben und die Queue um diese Nachricht verkleinert
% return: die tatsächlich verschickte MSGNr als Integer-Wert an den HBQ-Prozess

deliverMSG(MSGNr, ClientPID, {Size, Queue}) ->
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % deliverMSG(MSGNr, ClientPID, Queue, Datei)
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  util:logging(?QUEUE_LOGGING_FILE,
    "Body of dilverMSG logging routine for MSGNr" ++
      util:logging(?QUEUE_LOGGING_FILE, MSGNr) ++
      " \n"
  ),

  {_Size,SortedQueue} = sortDLQ({Size, Queue}),

  util:logging(?QUEUE_LOGGING_FILE,
    "Body of dilverMSG logging routine Sort DLQ  {_Size,SortedQueue}:" ++
      util:logging(?QUEUE_LOGGING_FILE, {_Size,SortedQueue}) ++
      " \n"),

  Result = lists:keyfind(MSGNr,1,SortedQueue),
  {NNr, Msg, TSclientout, TShbqin, TSdlqin} = findMessage(SortedQueue,MSGNr,Result),

  Exists = lists:any(fun({_NNr, _, _, _, _}) -> _NNr > NNr end, SortedQueue),

  util:logging(?QUEUE_LOGGING_FILE,
    "Set Exists Flag is:" ++
      util:logging(?QUEUE_LOGGING_FILE, Exists) ++
      " \n"),

  Tsdlqout = erlang:timestamp(),
  NewMessage = {reply,[NNr, Msg, TSclientout, TShbqin, TSdlqin,Tsdlqout],Exists},
  ClientPID ! NewMessage.



% findMessage(SortedQueue, MSGNr, Gefunden)

% Suche nach einer gegeben Nachrichtennummer in einer sortierten Queue

% pre: die Queue ist eine Liste und die MSGNr ist eine Nummer
% post: Die Queue wurde nich veraender
% return: Die Nachricht als Tupel mit der Nachrichtennummer

%% todo beheben wenn zeit und bedarf und lust
findMessage([],_, _) ->
  {0, "DUMMY", "DUMMY", "DUMMY", "DUMMY"} ;

findMessage(SortedQueue,MSGNr, false) ->
  findMessage(SortedQueue,MSGNr +1,lists:keyfind(MSGNr +1 ,1,SortedQueue));

findMessage(_,_,{NNr, Msg, TSclientout, TShbqin, TSdlqin}) ->
  {NNr, Msg, TSclientout, TShbqin, TSdlqin}.


% last(DLQ)

% Holt das letzte Element der DLQ

% pre: eine korrekte DLQ wurde uebergeben
% post: Wir haben die letzte Nachricht der DLQ
% return: gibt das letzte Element der Liste der DLQ zuruck

last({_,[]}) ->
  1;
last({_,List}) ->
  lists:last(List).

% sortDLQ(DLQ)

% Sortiert die DLQ anhang der Nachrichtennummern

% pre: eine korrekte DLQ wurde uebergeben in einer beliebigen reihenfolge
% post: die uebergebene DLQ ist in aufsteigender Nachrichtennummer folge
% return: Gibt die sortierte DLQ zurueck

sortDLQ({Size,Queue}) ->
  ORDER = fun({NNr, _, _, _, _},{_NNr, _, _, _, _}) ->
    NNr < _NNr end,
  {Size,lists:usort(ORDER,Queue)}.


% expectedNrDLQ(DLQ)

% Als nächstes zu speichernde Nachrichtennummer wird gefunden, falls
% die DLQ leer ist wird eine 1 zurueck gegeben

% pre: eine Queue in Form der DLQ-ADT
% post: Queue ist unverändert und eine korrekte Nachrichtennummer wurde zurückgegeben
% return: nächste Nachrichtennummer die verwendet werden kann, sonst 1 bei leerer Liste

expectedNrDLQ({_,[]}) ->
  1;
expectedNrDLQ({_,SortedDLQ}) ->
  {NNr, _, _, _, _} = lists:last(SortedDLQ),
  NNr +1.