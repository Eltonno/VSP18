%%%-------------------------------------------------------------------
%%% @author Elton
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 02. Apr 2015 10:06 AM
%%%-------------------------------------------------------------------
-module(hbq).
-author("Elton").
-export([initHBQandDLQ/2, start/0]).
-define(QUEUE_LOGGING_FILE, "HBQ.txt").



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DLQ Datentyp
%
% {[{NNr, Msg, TSclientout, TShbqin}}, ...]}
% {[Int, String, {Int, Int, Int}, {Int, Int, Int}}, ...]}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%start()

%% Definition: Startet einen neuen HBQ-Prozess, der die HBQ verwaltet und alleinigen Zugriff auf die DLQ besitzt.

% pre: Server-Prozess ist gestartet
% post: Es wurde ein neuer HBQ-Prozess gestartet der nun vom Server verwendet werden kann
% return: hbq-process started als Atom sonst eine sinnvolle Error-Meldung


start() ->
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


% loop()

% Die Hauptschleife der HBQ wartet auf Anfragen bzgl. des Servers.

% pre: keine
% post: der Prozess wurde erfolgreich terminiert
% return: hbq-process terminated als Atom

loop(DlqLimit, HBQname, HBQ, DLQ) ->
  receive

    {ServerPID, {request, initHBQ}} ->


      {_HBQ, _DLQ} = initHBQandDLQ(DlqLimit, ServerPID),

      util:logging(?QUEUE_LOGGING_FILE,
        "Die HBQ && DLQ wurden Initialisiert, der Inhalt {_HBQ, _DLQ}: " ++
          util:to_String( {_HBQ, _DLQ}) ++
          "\n"
      )


      , loop(DlqLimit, HBQname, _HBQ, _DLQ)
  ;
    {ServerPID, {request, pushHBQ, [NNr, Msg, TSclientout]}} ->
      _NewHBQ = pushHBQ(ServerPID, HBQ, [NNr, Msg, TSclientout]),

      util:logging(?QUEUE_LOGGING_FILE,
        "Die HBQ hat einen request für pushHBQ erhalten, mit der Message:" ++
          util:to_String([NNr, Msg, TSclientout]) ++
          "Die Nachricht wurde in die HBQ eingetragen, die HBQ vor dem Eintragen:" ++
          util:to_String(HBQ) ++
          "Die  die _NewHBQ nach dem Eintragen:" ++
          util:to_String(_NewHBQ) ++
          "\n"
      )

      , {NewHBQ, NewDLQ} = pushSeries(_NewHBQ, DLQ)

      , util:logging(?QUEUE_LOGGING_FILE,
        "Es wurde PushSeries für  (_NewHBQ, DLQ):" ++
          util:to_String([_NewHBQ, DLQ]) ++
          " ausgeführt. Das Ergebnis von PushSeries  {NewHBQ, NewDLQ}:" ++
          util:to_String({NewHBQ, NewDLQ}) ++
          "\n"
      )

      , loop(DlqLimit, HBQname, NewHBQ, NewDLQ)

  ;
    {ServerPID, {request, deliverMSG, NNr, ToClient}} ->

      util:logging(?QUEUE_LOGGING_FILE,
        "Es wurde deliverMSG für die MessageNr:" ++
          util:to_String(NNr) ++
          " Die DLQ mit dem Inhalt:" ++
          util:to_String(DLQ) ++
          " wird mit dem ausliefern in deliverMSG beauftragt" ++
          "\n"
      ),

      deliverMSG(ServerPID, DLQ, NNr, ToClient)
      , loop(DlqLimit, HBQname, HBQ, DLQ)
  ;
    {ServerPID, {request, dellHBQ}} ->
      dellHBQ(ServerPID, HBQname)


  end.


% initHBQandDLQ(ServerPID)

%% Initialisiert die HBQ und DLQ. Ruft die Methode „initDLQ(Size, Datei)“ in dem Modul in der DLQ auf

% pre: Ein korrekt Size und eine korrekte ServerPID wurde uebegeben
% post: ein 2-Tupel wurde erstellt. Das 1. Element ist die HBQ und das 2. Element die DLQ.
% return: 2-Tupel: {[], DLQ}

initHBQandDLQ(Size, ServerPID) ->
  util:logging("Die HBQ und DLQ wurden initialisiert",?QUEUE_LOGGING_FILE),
  DLQ = dlq:initDLQ(Size, ?QUEUE_LOGGING_FILE),
  ServerPID ! {reply, ok},
  {[], DLQ}.


% pushHBQ(ServerPID, OldHBQ, [NNr, Msg, TSclientout])

% Fügt eine Nachricht an die HBQ an

% pre: ServerPID mit der der Server erreicht werden kann, sowie eine korrekte OldHBQ.
% post: Der alten HBQ wurde ein neues Element beigefügt und der Server hat eine Nachricht erhalten.
% return: NewHBQ

pushHBQ(ServerPID, OldHBQ, [NNr, Msg, TSclientout]) ->
  Tshbqin = erlang:timestamp(),
  %erlang:display("das ist die queue"++util:to_String(OldHBQ)),
  %erlang:display("das ist die neue queue"++util:to_String(OldHBQ ++ [{NNr, Msg, TSclientout, Tshbqin}])),
  SortedHBQ = sortHBQ(OldHBQ ++ [{NNr, Msg, TSclientout, Tshbqin}]),
  ServerPID ! {reply, ok},
  SortedHBQ.

% deliverMSG(ServerPID, DLQ, NNr, ToClient), erweitert fuer logging

% Definition: Beauftragt die DLQ die Nachricht mit geforderter NNr an den Client (ToClient) zu senden.

% pre: korrekte Server-und ClientPID unter die beide Prozesse zu erreichen sind
% post: Der Client hat eine neue Nachricht erhalten, die DLQ ist um eine Nachricht kleiner geworden und dem Server wurde die Nachricht verschickt
% return: Atom ok wird zurückgegeben

deliverMSG(ServerPID, DLQ, NNr, ToClient) ->
  {reply, [MSGNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], Terminated} = dlq:deliverMSG(NNr, ToClient, DLQ),
  % ToClient ! {reply, [MSGNr, Msg, TSclientout, TShbqin, TSdlqin, TSdlqout], Terminated},
  ServerPID ! {reply, MSGNr}.


% dellHBQ(ServerPID)

% Definition: Terminiert den HBQ-Prozess und schickt dem Server eine Bestaetigung

% pre: korrekte ServerPID
% post: der Prozess wurde erfolgreich beendet
% return: Atom ok wird zurückgegeben

dellHBQ(ServerPID, HBQname) ->
  erlang:unregister(HBQname),
  ServerPID ! {reply, ok}.

% pushSeries(HBQ, {Size, Queue})

% Prüft auf Nachrichten / Nachrichtenfolgen, die ohne eine Lücke zu bilden in die DLQ eingefügt werden können.

% pre: korrekt initialisierte HBQ- und DLQ-Datenstruktur
% post: veränderte HBQ- und DLQ-Datenstruktur
% return: {HBQ, DLQ} als 2-Tupel

pushSeries(HBQ, {Size, Queue}) ->

  %TODO TEST THAT SHEET WITH UNSORTED DLQ CAUSE DLQ SHOULD BE ALREADY SORTED
  ExpectedMessageNumber = dlq:expectedNrDLQ(dlq:sortDLQ({Size, Queue})),

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


% push_consistent_block_to_dlq(ConsistentBlock,DLQ)

% Ubergibt einen konsistenten Block an die DLQ

% pre: Einen konsistenten Block an Nachrichten und die DLQ
% post: veränderte HBQ- und DLQ-Datenstruktur
% return: {HBQ, DLQ} als 2-Tupel

push_consisten_block_to_dlq(ConsistentBlock, DLQ) ->
  push_consisten_block_to_dlq_(ConsistentBlock, DLQ).

push_consisten_block_to_dlq_([H | T], DLQ) ->
  NewDLQ = dlq:push2DLQ(H, DLQ, ?QUEUE_LOGGING_FILE),
  push_consisten_block_to_dlq_(T, NewDLQ);

push_consisten_block_to_dlq_([], DLQ) ->
  DLQ.


% create_consisten_block(ConsistentBlock,DLQ)

% Erstellt einen konsistenten Nachrichtenblock aus einer Liste

% pre: Eine Liste
% post: Die laengste aufeinanderfolgende Nachrichtennummer folge aus der Liste wurde in die DLQ eingefuegt
% return: Die laengste aufeinanderfolgende Nachrichtennummer folge aus der Liste


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

