/-  *pokur
|%
::
::  game-state transition core
::
++  guts
  |_  state=host-game-state
  ::
  ::  entry point for host
  ::  **takes in a shuffled deck**
  ::  assign dealer, assign blinds, assign first action
  ::  to person left of BB (which is dealer in heads-up)
  ::  make sure to shuffle deck from outside with eny!!!
  ::  check for players who have left, remove them
  ::
  ++  initialize-hand
    ^-  host-game-state
    =:  hands.state                ~
        last-aggressor.game.state  ~
        last-action.game.state     ~
        board.game.state           ~
        current-bet.game.state     0
        last-bet.game.state        0
        hand-is-over.state         %.n
    ==
    ::  remove any players who have left the table
    =.  players.game.state
      %+  murn  players.game.state
      |=  [p=@p player-info]
      ?:  left  ~
      `[p stack committed %.n ?:(=(0 stack) %.y %.n) %.n]
    =.  dealer.game.state
      (next-active-player:gang dealer.game.state)
    =.  state  deal-hands
    =.  state  assign-blinds
    =.  whose-turn.game.state
      (next-active-player:gang big-blind.game.state)
    =.  pots.game.state
      :_  ~  :-  0
      %+  murn  players.game.state
      |=([p=@p player-info] ?:(folded ~ `p))
    state
  ::
  ::  deals 2 cards from deck to each player in game
  ::  only deal to players who are not "out": stack=0
  ::
  ++  deal-hands
    ^-  host-game-state
    =/  players  players.game.state
    |-
    ?~  players  state
    ?:  =(0 stack.i.players)
      $(players t.players)
    =/  drawn  (draw 2 deck.state)
    %=  $
      players      t.players
      deck.state   rest.drawn
      hands.state  (~(put by hands.state) ship.i.players hand.drawn)
    ==
  ::
  ::  takes blinds from the two active players left of dealer
  ::  (in heads up, dealer is small blind)
  ::
  ++  assign-blinds
    ^-  host-game-state
    =.  small-blind.game.state
      ?:  =(~(wyt by hands.state) 2)
        dealer.game.state
      (next-active-player:gang dealer.game.state)
    ::
    =.  big-blind.game.state
      (next-active-player:gang small-blind.game.state)
    ::  if game type is %cash, use set blinds
    ::  if %tournament, set blinds based on round we're on
    =/  blinds  (get-current-blinds game-type.game.state)
    =.  players.game.state
      (commit-chips:gang small-blind.game.state small.blinds)
    %=  state
      current-bet.game  big.blinds
      last-bet.game     big.blinds
      players.game  (commit-chips:gang big-blind.game.state big.blinds)
    ==
  ::
  ::  other entry point for host
  ::  given a player and a pokur-action, handles the action.
  ::  returns a unit for pokur-host to either ingest or reject
  ::  currently checks for being given the wrong player (not their turn),
  ::  bad bet (<2x existing bet, >BB, or matches current bet (call)),
  ::  and trying to check when there's a bet to respond to.
  ::  if betting is complete, go right into flop/turn/river/determine-winner
  ::  * folds trigger win for last standing player
  ::
  ++  process-player-action
    |=  [who=ship action=game-action]
    ^-  (unit host-game-state)
    ?>  =(who whose-turn.game.state)
    =.  update-message.game.state  ''
    ?~  i=(get-player-info:gang who)  ~
    =*  player-info  u.i
    ?-    -.action
        %check
      ?.  =(current-bet.game.state committed.player-info)
        ~
      ::  set checking player to 'acted'
      =:  players.game.state      (set-player-as-acted:gang who)
          last-action.game.state  `%check
      ==
      `next-player-turn
    ::
        %fold
      =.  players.game.state  (set-player-as-acted:gang who)
      =.  players.game.state  (set-player-as-folded:gang who)
      =.  update-message.game.state  (crip "{<who>} folded. ")
      ::  remove folding player from ALL pots
      =.  pots.game.state
        %+  turn  pots.game.state
        |=  [amount=@ud in=(list ship)]
        [amount (skip in |=(p=@p =(p who)))]
      ::  if only one player hasn't folded, process win for them
      =/  players-left
        %+  skip  players.game.state
        |=([ship ^player-info] folded)
      ?:  =(1 (lent players-left))
        ::  NOT showdown
        `(process-win [-.-.players-left [0 ~]]~ %.n)
      :: otherwise continue game
      =.  last-action.game.state  `%fold
      `next-player-turn
    ::
        %bet
      =/  bet-plus-committed
        (add amount.action committed.player-info)
      =/  current-min-bet
        %+  min
          big:(get-current-blinds game-type.game.state)
        ::  largest stack of still-in player, excluding active one
        %+  roll
          %+  murn  players.game.state
          |=  [=ship ^player-info]
          ?:  |(=(0 stack) =(ship who) =(folded &) =(left &))
            ~
          `stack
        max
      ?:  (gte amount.action stack.player-info)
        ::  ALL-IN logic here
        =.  game.state
          ?:  (gth bet-plus-committed current-bet.game.state)
            ::  this is a "raise" all-in, update necessary trackers
            %=  game.state
              current-bet     bet-plus-committed
              last-bet        (sub bet-plus-committed current-bet.game.state)
              last-aggressor  `who
              last-action     `%raise
            ==
          ::  this is a "call" all-in
          %=  game.state
            last-action     `%call
          ==
        =.  players.game.state  (commit-chips:gang who stack.player-info)
        =.  players.game.state  (set-player-as-acted:gang who)
        =.  update-message.game.state  (crip "{<who>} is all-in. ")
        `next-player-turn
      ::  resume logic for not-all-in
      ?:  ?&  =(current-bet.game.state 0)
              (lth bet-plus-committed current-min-bet)
          ==
        ~  ::  this is a starting bet below min-bet
      ?:  =(bet-plus-committed current-bet.game.state)
        ::  this is a call
        =.  players.game.state      (commit-chips:gang who amount.action)
        =.  players.game.state      (set-player-as-acted:gang who)
        =.  last-action.game.state  `%call
        `next-player-turn
      ::  this is a raise attempt
      ::  the raise must either be >= amount of previous bet/raise,
      ::  OR must put the other remaining player with the most chips all-in.
      ?.  ?|  %+  gte  bet-plus-committed
              (add last-bet.game.state current-bet.game.state)
              ?&  %+  lth  current-min-bet
                  big:(get-current-blinds game-type.game.state)
                  (gte bet-plus-committed current-min-bet)
          ==  ==
        ~
      ::  process raise
      =:  last-aggressor.game.state  `who
          last-action.game.state     `%raise
      ==
      ::  do this before updating current-bet
      =.  last-bet.game.state
        (sub bet-plus-committed current-bet.game.state)
      =.  current-bet.game.state  bet-plus-committed
      =.  players.game.state  (commit-chips:gang who amount.action)
      =.  players.game.state  (set-player-as-acted:gang who)
      `next-player-turn
    ==
  ::
  ::  sets whose-turn to next active player in list, or,
  ::  if the next active player is same as current player,
  ::  go into next betting round.
  ::
  ++  next-player-turn
    ^-  host-game-state
    =+  next=(next-active-player:gang whose-turn.game.state)
    ?:  |(betting-is-over =(- whose-turn.game.state))
      next-betting-round
    state(whose-turn.game -)
  ::
  ::  check if every player has either folded, is
  ::  all-in, or (acted AND committed = current bet)
  ::
  ++  betting-is-over
    ^-  ?
    %+  levy  players.game.state
    |=  [ship player-info]
    ?|  folded
        ?|  =(0 stack)
            ?&  acted
                =(committed current-bet.game.state)
    ==  ==  ==
  ::
  ::  checks cards on game and either initiates flop,
  ::  turn, river, or determine-winner
  ::
  ++  next-betting-round
    ^-  host-game-state
    ::  check if we are in "showdown"
    ::  mode and reveal hands if so.
    =/  all-ins  all-in-players:gang
    =/  showdown-mode  ?=(^ all-ins)
    =.  revealed-hands.game.state
      ?.  showdown-mode  ~
      %+  turn  all-ins
      |=(=ship [ship (~(got by hands.state) ship)])
    |^
    ::  loop if showdown mode is on
    |-
    =/  n  (lent board.game.state)
    ?:  =(0 n)
      ::  flop
      =.  state  committed-chips-to-pot
      (deal-to-board 3)
    ?:  |(=(3 n) =(4 n))
      ::  turn, river
      =.  state  committed-chips-to-pot
      (deal-to-board 1)
    ::  showdown
    %-  process-win  :_  %.y
    %+  determine-winner  board.game.state
    %+  murn  players.game.state
    |=  [who=ship player-info]
    ?:  folded  ~
    `[who (~(got by hands.state) who)]
    ::
    ::  draws n cards (after burning 1) from deck,
    ::  appends them to end of board, and sets action
    ::  to the next unfolded player left of dealer
    ::
    ++  deal-to-board
      |=  n=@ud
      ^-  host-game-state
      =/  turn  (draw n rest:(draw 1 deck.state))  ::  burn
      =.  deck.state  rest:turn
      =.  board.game.state  (weld board.game.state hand:turn)
      ::  if we are in showdown mode, skip next-player-turn
      ::  and go straight to next-betting-round
      ?:  showdown-mode  ^$
      ::  setting who goes first in betting round here
      =.  whose-turn.game.state  dealer.game.state
      next-player-turn
    --
  ::
  ::  put all committed chips from a single betting round into pot.
  ::  a player can only be involved in a pot that they contribute to:
  ::  we look at the smallest committed value, then add the matching values
  ::  from each involved player into the current pot.
  ::  then, look at next smallest until reaching highest committed value,
  ::  producing a new pot at every discrete value, with ties matching
  ::
  ++  committed-chips-to-pot
    ^-  host-game-state
    =/  sorted-commitments=players
      %+  sort
        %+  skip  players.game.state
        |=  [p=@p player-info]
        =(0 committed)
      |=  [a=[ship player-info] b=[ship player-info]]
      (lth committed.a committed.b)
    ::  ~&  >  sorted-commitments
    =/  this-pot  (rear pots.game.state)
    =/  new-pot=?
      ::  if last pot had more players than current commitments,
      ::  start out making a new pot
      (lth (lent sorted-commitments) (lent in.this-pot))
    |-
    ?:  =(~ sorted-commitments)
      ::  all pots built, finished
      ::  ~&  >>  pots.game.state
      %=  state
        current-bet.game  0
        last-bet.game     0
      ::
          players.game
        %+  turn  players.game.state
        |=  [=ship i=player-info]
        [ship i(committed 0, acted %.n)]
      ==
    ::  take lowest commitment and add from all to current pot
    =/  lowest=[ship player-info]  (head sorted-commitments)
    ::  grab the current active pot from list to modify first
    =/  [less=players added-chips=@ud]
      %^  spin  sorted-commitments  ?:(new-pot 0 -.this-pot)
      |=  [[p=ship i=player-info] pot=@ud]
      :-  [p i(committed (sub committed.i committed.lowest))]
      (add pot committed.lowest)
    %=    $
        sorted-commitments
      ::  remove not just the lowest commitment, but any player who now
      ::  has 0 committed chips
      %+  skip  less
      |=([ship player-info] =(0 committed))
    ::
        pots.game.state
      ::  if this is a new side pot, stack on top
      ::  if not, replace current rear pot with this one
      ?:  new-pot
        %+  snoc  pots.game.state
        [added-chips (turn less head)]
      %+  snoc
        (snip pots.game.state)
      this-pot(amount added-chips)
    ::
        new-pot
      ?:  |(folded.lowest =(0 committed.lowest))  %.n  %.y
    ::
        this-pot
      ?:  |(folded.lowest =(0 committed.lowest))
        this-pot(amount added-chips)
      [0 (turn (tail sorted-commitments) head)]
    ==
  ::
  ::  this gets called when a tournament round timer runs out
  ::  it tells us to increment when current hand is over
  ::  and sets an update message in the game state
  ::
  ++  increment-current-round
    ^-  host-game-state
    ?>  ?=(%sng -.game-type.game.state)
    =/  next-round
      +(current-round.game-type.game.state)
    =/  blinds=[small=@ud big=@ud]
      ?:  (gte next-round (lent blinds-schedule.game-type.game.state))
        (rear blinds-schedule.game-type.game.state)
      %+  snag  next-round
      blinds-schedule.game-type.game.state
    %=  state
      round-is-over.game-type.game  %.y
        update-message.game
      %-  crip
      """
      Round {<next-round>} beginning at next hand.
      New blinds: {<small.blinds>}/{<big.blinds>}
      """
    ==
  ::
  ::  given a list of winners, send them the pot. prepare for next
  ::  hand by clearing board, hands and bets, reset fold status,
  ::  and incrementing hands-played.
  ::  also, see if any players have gotten out and place them (for tournaments)
  ::
  ++  process-win
    |=  [winners=(list [ship [@ud pokur-deck]]) showdown=?]
    ^-  host-game-state
    ::  sends any extra committed chips to pot
    =.  state  committed-chips-to-pot
    =.  state  (award-pots winners showdown)
    =?    state
        ?&  ?=(%sng -.game-type.game.state)
            round-is-over.game-type.game.state
        ==
      %=    state
          current-round.game-type.game
        +(current-round.game-type.game.state)
          round-is-over.game-type.game
        %.n
      ==
    =/  active-with-chips
      %+  skip  players.game.state
      |=  [p=ship player-info]
      |(=(0 stack) left)
    %=  state
      hand-is-over       %.y
      deck               generate-deck  ::  need a fresh 52-card one
      hands-played.game  +(hands-played.game.state)
    ::
        game-is-over.game
      =-  |(=(1 -) =(0 -))
      (lent active-with-chips)
    ::
        placements
      ::  re-order player placements based on stacks
      ::  if player already has stack=0, their placement is locked in
      ::  if not, re-order with other players based on stacks
      (reorder-placements:gang placements.state)
    ::
        players.game
      %+  turn  players.game.state
      |=  [p=ship i=player-info]
      ?.  =(0 stack.i)  [p i]
      [p i(acted %.y, folded %.y)]
    ==
  ::
  ::  sent pot and any side pots to deserving winners
  ::  if showdown, reveal hand of winner(s) and last-aggressor
  ::
  ++  award-pots
    |=  [winners=(list [ship [@ud pokur-deck]]) showdown=?]
    ^-  host-game-state
    |-
    ?~  pots.game.state  state
    ::  if we don't already have a set of revealed hands from an
    ::  all-in, reveal winner and last-aggressor (if we're at showdown)
    =?    revealed-hands.game.state
        &(showdown ?=(~ revealed-hands.game.state))
      %+  turn
        ?~  last=last-aggressor.game.state
          (turn winners head)
        =+  w=(turn winners head)
        ?^  (find ~[u.last] w)  w
        [u.last w]
      |=(p=ship [p (~(got by hands.state) p)])
    ::
    =*  pot  i.pots.game.state
    =/  winners-in-pot=(list [ship [@ud pokur-deck]])
      ?.  showdown  winners  ::  will be 1 player
      %+  skip  winners
      |=  [p=ship [@ud pokur-deck]]
      =(~ (find [p]~ in.pot))
    =?    winners-in-pot
        =(~ winners-in-pot)
      ::  no winners in this pot, find the relative winner(s) present
      ::  this must only occur at showdown, if the best hand went all-in
      ::  prior to this side-pot and therefore doesn't deserve it
      ::  if a pot is to be awarded before showdown, the player that
      ::  was folded to will be in all pots.
      %+  determine-winner  board.game.state
      %+  skim  ~(tap by hands.state)
      |=  [=ship hand=pokur-deck]
      ?=(^ (find [ship]~ in.pot))
    %=  $
      pots.game.state  t.pots.game.state
    ::
        update-message.game.state
      %^  cat  3
        ?:  =(1 (lent winners-in-pot))
          ;:  (cury cat 3)
            update-message.game.state
            (scot %p -.-.winners-in-pot)
            ' wins pot of '
            (scot %ud amount.pot)
          ==
        ;:  (cury cat 3)
          update-message.game.state
          %+  roll
            %+  turn  winners-in-pot
            |=([p=@ *] (cat 3 (scot %p p) ', '))
          (cury cat 3)
          'split pot of '
          (scot %ud amount.pot)
        ==
      ?.  showdown
        '. '
      ;:  (cury cat 3)
        ' with hand '
        (hierarchy-to-rank -.+.-.winners-in-pot)
        '.  '
      ==
    ::
        players.game.state
      ?:  =(1 (lent winners-in-pot))
        ::  award entire pot to single winner
        %+  turn  players.game.state
        |=  [p=ship player-info]
        ?.  =(p -.-.winners-in-pot)
          [p stack 0 %.n %.n left]
        [p (add stack amount.pot) 0 %.n %.n left]
      ::  split pot evenly between multiple winners
      =/  split  (div amount.pot (lent winners-in-pot))
      %+  turn  players.game.state
      |=  [p=ship player-info]
      ?~  (find [p]~ (turn winners-in-pot head))
        [p stack 0 %.n %.n left]
      [p (add stack split) 0 %.n %.n left]
    ==
  ::
  ::  if the host allows, players can join at any time.
  ::  players enter as acted+folded, and will be set to active at the
  ::  beginning of next hand. new players will be seated behind
  ::  current dealer. if player is already in players-list, assert that
  ::  they had left, then replace their entry.
  ::
  ++  add-player
    |=  [who=ship starting-stack=@ud]
    ^-  host-game-state
    =/  found  (find ~[who] (turn players.game.state head))
    =?    players.game.state
        ?=(^ found)
      (oust [u.found 1] players.game.state)
    %=    state
        players.game
      =+  pos=(find ~[dealer.game.state] (turn players.game.state head))
      %^  into  players.game.state
        ?~(pos 0 u.pos)
      [who `player-info`[starting-stack 0 %.y %.y %.n]]
    ::
        update-message.game
      (crip "{<who>} joined the game. ")
    ==
  ::
  ::  set player to folded+acted+left
  ::  if it was their turn, go to next player's turn
  ::
  ++  remove-player
    |=  who=ship
    ^-  host-game-state
    =.  game-is-over.game.state
      =-  |(=(2 -) =(1 -))
      (lent players.game.state)
    =.  players.game.state
      %+  turn  players.game.state
      |=  [p=ship i=player-info]
      ?.  =(p who)  [p i]
      [p i(acted %.y, folded %.y, left %.y)]
    ::  remove folding player from current pot
    =.  pots.game.state
      ?:  =(~ pots.game.state)  ~
      %+  snoc
        (snip pots.game.state)
      =+  (rear pots.game.state)
      [-.- (skip `(list @p)`+.- |=(p=@p =(p who)))]
    =.  update-message.game.state
      (crip "{<who>} left the game. ")
    =/  players-left
      %+  skip  players.game.state
      |=([ship player-info] folded)
    ?:  =(1 (lent players-left))
      ::  will handle ending game
      (process-win [-.-.players-left [0 ~]]~ %.n)
    ::  otherwise continue game
    ?.  =(who whose-turn.game.state)  state
    next-player-turn
  ::
  ::  player-list utils core
  ::
  ++  gang
    |%
    ++  get-player-info
      |=  who=ship
      ^-  (unit player-info)
      =-  ?~  -  ~  `+:(head -)
      %+  skim  players.game.state
      |=([p=ship player-info] =(p who))
    ::
    ::  return player next in turn-order who has not folded,
    ::  not left, and is not all-in
    ::
    ++  next-active-player
      |=  current=ship
      ^-  ship
      =/  unfolded-players
        %+  skim  players.game.state
        |=  [p=ship player-info]
        ::  player must be not folded, not left, and stack > 0
        ::  current player is kept in to indicate where to increment from
        ?|  =(p current)
            ?&(!folded !left !=(0 stack))
        ==
      ?~  pos=(find [current]~ (turn unfolded-players head))
        ::  this will never happen
        current
      %-  head
      %+  snag
        (mod +(u.pos) (lent unfolded-players))
      unfolded-players
    ::
    ::  check if all (or all but one) players remaining in hand are all-in
    ::  produces a list of ships that are "locked into" hand
    ::  must be used after a betting round is over
    ::
    ++  all-in-players
      ^-  (list ship)
      =/  actionable-players
        %+  murn  players.game.state
        |=  [=ship player-info]
        ?.  &(!folded (gth stack 0))  ~
        `ship
      ?.  (lte (lent actionable-players) 1)
        ~
      %+  weld
        actionable-players
      %+  murn  players.game.state
      |=  [=ship player-info]
      ?.  &(!folded =(0 stack))  ~
      `ship
    ::
    ::  sends chips from player's 'stack' to their 'committed' pile.
    ::  committed chips don't go to pot until round of betting is complete.
    ::  if player doesn't have enough chips, put them all-in!
    ::
    ++  commit-chips
      |=  [who=ship amount=@ud]
      ^-  players
      %+  turn  players.game.state
      |=  [p=ship i=player-info]
      ?.  =(p who)  [p i]
      ?:  (gth amount stack.i)
        ::  all-in
        [p i(committed (add committed.i stack.i), stack 0)]
      [p i(committed (add committed.i amount), stack (sub stack.i amount))]
    ::
    ++  set-player-as-acted
      |=  who=ship
      ^-  players
      %+  turn  players.game.state
      |=  [p=ship i=player-info]
      ?.  =(p who)  [p i]
      [p i(acted %.y)]
    ::
    ++  set-player-as-folded
      |=  who=ship
      ^-  players
      %+  turn  players.game.state
      |=  [p=ship i=player-info]
      ?.  =(p who)  [p i]
      [p i(folded %.y)]
    ::
    ::  keep an ordering of players based on chip-count at end of each hand
    ::
    ++  reorder-placements
      |=  places=(list ship)
      ^-  (list ship)
      ::  sort players list by stack size, break ties by using their
      ::  *previous* rank in places list
      ::  any players who have left are treated as stack=0
      %-  turn  :_  head
      %+  sort  players.game.state
      |=  [a=[=ship player-info] b=[=ship player-info]]
      ?:  ?&(!left.a left.b)  %.y
      ?:  ?&(left.a !left.b)  %.n
      ?:  (gth stack.a stack.b)  %.y
      ?:  (lth stack.a stack.b)  %.n
      %+  gth
        ?~  ax=(find ~[ship.a] places)  0  u.ax
      ?~  bx=(find ~[ship.b] places)  0  u.bx
    --
  --
::
::  random utils
::
++  parse-time-limit
  |=  tex=@t
  ^-  @dr
  ?>  (lth (slav %ud tex) 1.000)
  (slav %dr `@t`(cat 3 '~s' tex))
::
++  get-current-blinds
  |=  =game-type
  ^-  [small=@ud big=@ud]
  ?:  ?=(%cash -.game-type)
    [small-blind big-blind]:game-type
  ?:  %+  gte  current-round.game-type
      (lent blinds-schedule.game-type)
    (rear blinds-schedule.game-type)
  (snag [current-round blinds-schedule]:game-type)
::
::  Hand evaluation and sorted helper arms
::
::  takes a list of hands and finds winning hand. This is only called
::  when the board is full, so it deals with all 7-card hands.
::  It returns a list of winning ships, which usually contains just
::  the one, but can have up to n ships all tied.
++  determine-winner
  |=  [board=pokur-deck hands=(list [ship pokur-deck])]
  ^-  (list [ship [@ud pokur-deck]])
  ?>  =(5 (lent board))
  =/  hand-ranks
    %+  turn  hands
    |=  [who=ship hand=pokur-deck]
    [who (evaluate-7-card-hand (weld hand board))]
  ::  return player with highest hand rank
  =/  player-ranks=(list [ship @ud hand=pokur-deck])
    %+  sort  hand-ranks
    |=  [a=[@ [r=@ud *]] b=[@ [r=@ud *]]]
    (gth r.a r.b)
  ::  check for ties and return winner(s)
  =/  top-rank  -.+.-.player-ranks
  ?:  =(1 (lent player-ranks))
    -.player-ranks^~
  ?.  =(top-rank -.+.+<.player-ranks)
    ::  no ties, proceed
    -.player-ranks^~
  ::  some players have equally-ranked hands
  =.  player-ranks
    %+  sort  player-ranks
    |=  [a=[@ [r=@ud h=pokur-deck]] b=[@ [r=@ud h=pokur-deck]]]
    ?:  =(r.a r.b)
      (break-ties +.a +.b)
    (gth r.a r.b)
  ::  then check for identical hands, in which case pot must be split.
  ?~  player-ranks  -.player-ranks^~
  =/  best-hand  hand.i.player-ranks
  %+  skim
    `(list [ship @ud hand=pokur-deck])`player-ranks
  |=  [ship @ud hand=pokur-deck]
  (hands-equal hand best-hand)
::  +evaluate-7-card-hand: returns a cell of [hierarchy-number hand]
::  where hand is the *strongest possible 5 card hand*.
++  evaluate-7-card-hand
  |=  hand=pokur-deck
  ^-  [@ud pokur-deck]
  =/  removal-pairs=(list [@ud @ud])
    :~  [0 1]  [0 2]  [0 3]  [0 4]  [0 5]  [0 6]
        [1 2]  [1 3]  [1 4]  [1 5]  [1 6]
        [2 3]  [2 4]  [2 5]  [2 6]
        [3 4]  [3 5]  [3 6]
        [4 5]  [4 6]
        [5 6]
    ==
  =/  rank-sorted-5-card-hands=(list [@ud pokur-deck])
    %-  sort
    :_  |=([a=[@ud *] b=[@ud *]] (gth -.a -.b))
    ^-  (list [@ud pokur-deck])
    =|  ranked-hands=(list [@ud pokur-deck])
    |-
    ?~  removal-pairs  ranked-hands
    =+  %+  oust  [-.i.removal-pairs 1]
        (oust [+.i.removal-pairs 1] hand)
    %=  $
      removal-pairs  t.removal-pairs
      ranked-hands  [[(evaluate-5-card-hand -) -] ranked-hands]
    ==
  ::  elimate any hand without a score that matches top hand
  ::  if there are multiple, sort them by break-ties
  =/  best-hand-rank  -.-.rank-sorted-5-card-hands
  =/  best-5-card-hands
    %+  skim  rank-sorted-5-card-hands
    |=([r=@ud *] =(r best-hand-rank))
  ::  break any ties
  (head (sort best-5-card-hands break-ties))
:: arm for players to evaluate their hand before the river
:: this is the same as evaluate-7-card-hand, just with 6 cards
++  evaluate-6-card-hand
  |=  hand=pokur-deck
  ^-  [@ud pokur-deck]
  =/  removal-indices=(list @ud)  [0 1 2 3 4 5 ~]
  =/  rank-sorted-5-card-hands=(list [@ud pokur-deck])
    %-  sort
    :_  |=([a=[@ud *] b=[@ud *]] (gth -.a -.b))
    ^-  (list [@ud pokur-deck])
    =|  ranked-hands=(list [@ud pokur-deck])
    |-
    ?~  removal-indices  ranked-hands
    =+  (oust [i.removal-indices 1] hand)
    %=  $
      removal-indices  t.removal-indices
      ranked-hands  [[(evaluate-5-card-hand -) -] ranked-hands]
    ==
  ::  elimate any hand without a score that matches top hand
  ::  if there are multiple, sort them by break-ties
  =/  best-hand-rank  -.-.rank-sorted-5-card-hands
  =/  best-5-card-hands
    %+  skim  rank-sorted-5-card-hands
    |=([r=@ud *] =(r best-hand-rank))
  ::  break any ties
  (head (sort best-5-card-hands break-ties))
::  core hand evaluation function
::  assigns a rank to 5 card hand
++  evaluate-5-card-hand
  |=  hand=pokur-deck
  ^-  @ud
  ::  check for pairs with histogram of hand
  =/  raw-hand  (turn hand card-to-raw)
  =/  histogram=(list @ud)
    %-  sort  :_  gth
    %-  skip  :_  |=(n=@ud =(n 0))
    ^-  (list @ud)
    =/  histo  (reap 13 0)
    |-
    ?~  raw-hand  histo
    %=  $
      raw-hand  t.raw-hand
      histo  (snap histo -.i.raw-hand +((snag -.i.raw-hand histo)))
    ==
  ?:  =(histogram ~[4 1])      8  ::  four of a kind
  ?:  =(histogram ~[3 2])      7  ::  full house
  ?:  =(histogram ~[3 1 1])    3  ::  trips
  ?:  =(histogram ~[2 2 1])    2  ::  two pair
  ?:  =(histogram ~[2 1 1 1])  1  ::  pair
  ::  at this point, must sort hand
  =.  raw-hand
    (sort raw-hand |=([a=[@ud @ud] b=[@ud @ud]] (gth -.a -.b)))
  ::  check for flush, straight
  =/  is-straight=(unit @ud)  (check-5-card-straight raw-hand)
  ?:  (check-5-card-flush raw-hand)
    ?^  is-straight
      ?:  &(=(-.-.raw-hand 12) =(-.+>+>-.raw-hand 8))
        10  ::  royal flush!!!!
      9  ::  straight flush!
    6  ::  flush
  ?^  is-straight
    u.is-straight  ::  wheel or regular straight
  0  ::  high card
::
++  check-5-card-flush
  |=  raw-hand=(list [@ud @ud])
  ^-  ?
  =/  suit  +.-.raw-hand
  %+  levy  raw-hand
  |=(c=[@ud @ud] =(+.c suit))
::  **hand must be sorted before using this
::  returns rank 5 for regular straight,
::  rank 4 for wheel straight, 1 otherwise (%.n)
++  check-5-card-straight
  |=  raw-hand=(list [@ud @ud])
  ^-  (unit @ud)
  ?:  =(4 (sub -.-.raw-hand -.+>+>-.raw-hand))
    `5
  ::  also need to check for wheel straight
  ?:  &(=(-.-.raw-hand 12) =(-.+<.raw-hand 3))
    `4
  ~
:: given two hands, returns %.y if 1 is better than 2
:: *ONLY WORKS* for 5 card hands
++  break-ties
  |=  [hand1=[r=@ud h=pokur-deck] hand2=[r=@ud h=pokur-deck]]
  ^-  ?
  ::  if ranks are strictly better, just return that
  ::  otherwise break equally-ranked hands
  ?.  =(r.hand1 r.hand2)  (gth r.hand1 r.hand2)
  ::  sort whole hands to start
  =.  h.hand1  (sort h.hand1 card-compare)
  =.  h.hand2  (sort h.hand2 card-compare)
  ::  straight flushes rank by their top card, but in a wheel
  ::  the ace plays low, so it's 5-high
  ?:  =(r.hand1 9)
    (gth (straight-top h.hand1) (straight-top h.hand2))
  ::  match tie-breaking strategy to type of hand
  ?:  ?|  =(r.hand1 8)
          =(r.hand1 5)
          =(r.hand1 0)
        ==
    ::  these ties can be broken by just finding high card
    (find-high-card h.hand1 h.hand2)
  ::  other hands must be sorted by card frequency, then
  ::  high card within that frequency sorting
  %+  find-high-card
    (sort-hand-by-frequency h.hand1)
  (sort-hand-by-frequency h.hand2)
:: Sorts cards in pokur-deck by frequency of value, then rank
++  sort-hand-by-frequency
  |=  hand=pokur-deck
  ^-  pokur-deck
  %-  turn
  :_  head
  %+  sort
    ::  first add frequency to each card
    %+  turn  hand
    |=  c=pokur-card
    :-  c
    %-  lent
    %+  skim  hand
    |=([d=pokur-card] =(-.c -.d))
  ::  then sort by frequency, falling back to card rank
  |=  [a=[c=pokur-card freq=@ud] b=[c=pokur-card freq=@ud]]
  ?:  =(freq.a freq.b)
    (card-compare c.a c.b)
  (gth freq.a freq.b)
::  top card of a sorted straight, where A-2-3-4-5 is 5-high
++  straight-top
  |=  hand=pokur-deck
  ^-  @ud
  =/  top  (card-val-to-atom -:(snag 0 hand))
  ?:  &(=(12 top) =(3 (card-val-to-atom -:(snag 1 hand))))
    3
  top
:: Utility function to check if two hands are the same.
++  hands-equal
  |=  [h1=pokur-deck h2=pokur-deck]
  ^-  ?
  =.  h1  (sort h1 card-compare)
  =.  h2  (sort h2 card-compare)
  |-
  ?:  &(=(~ h1) =(~ h2))  %.y
  ?~  h1  %.n
  ?~  h2  %.n
  ?.  (cards-equal i.h1 i.h2)
    %.n
  $(h1 t.h1, h2 t.h2)
::  %.y if hand1 has higher card, %.n if hand2 does
::  hands must be sorted by card rank to use
++  find-high-card
  |=  [h1=pokur-deck h2=pokur-deck]
  ^-  ?
  ?~  h1  %.n
  ?~  h2  %.y
  ?.  (cards-equal i.h1 i.h2)
    (card-compare i.h1 i.h2)
  $(h1 t.h1, h2 t.h2)
::
++  card-compare
  |=  [c1=pokur-card c2=pokur-card]
  ^-  ?
  (gth (card-val-to-atom -.c1) (card-val-to-atom -.c2))
::
++  cards-equal
  |=  [c1=pokur-card c2=pokur-card]
  ^-  ?
  =((card-val-to-atom -.c1) (card-val-to-atom -.c2))
::
++  hierarchy-to-rank
  |=  h=@ud
  ^-  @t
  ?+  h  '-'
    %10  'Royal Flush'
    %9  'Straight Flush'
    %8  'Four of a Kind'
    %7  'Full House'
    %6  'Flush'
    %5  'Straight'
    %4  'Straight'  ::  A2345
    %3  'Three of a Kind'
    %2  'Two Pair'
    %1  'Pair'
    %0  'High Card'
  ==
::
++  card-to-raw
  |=  c=pokur-card
  ^-  [@ud @ud]
  [(card-val-to-atom -.c) (suit-to-atom +.c)]
::
++  card-val-to-atom
  |=  c=card-val
  ^-  @
  ?-  c
    %2      0
    %3      1
    %4      2
    %5      3
    %6      4
    %7      5
    %8      6
    %9      7
    %10     8
    %jack   9
    %queen  10
    %king   11
    %ace    12
  ==
::
++  suit-to-atom
  |=  s=suit
  ^-  @
  ?-  s
    %hearts    0
    %spades    1
    %clubs     2
    %diamonds  3
  ==
::
++  atom-to-card-val
  |=  n=@
  ^-  card-val
  ?+  n  !!
    %0   %2
    %1   %3
    %2   %4
    %3   %5
    %4   %6
    %5   %7
    %6   %8
    %7   %9
    %8   %10
    %9   %jack
    %10  %queen
    %11  %king
    %12  %ace
  ==
::
++  atom-to-suit
  |=  val=@
  ^-  suit
  ?+  val  !!
    %0  %hearts
    %1  %spades
    %2  %clubs
    %3  %diamonds
  ==
::  create a new 52 card poker deck
++  generate-deck
  ^-  pokur-deck
  =|  new-deck=pokur-deck
  =+  i=0
  |-
  ?:  (gth i 3)  new-deck
  =+  j=0
  |-
  ?.  (lte j 12)  ^$(i +(i))
  %=  $
    j         +(j)
    new-deck  [(atom-to-card-val j) (atom-to-suit i)]^new-deck
  ==
::
::  shuffle a list -- used to shuffle pokur deck,
::  and player list at start of game
::
::  DO NOT USE THIS FOR LARGE LISTS. IT IS EXTREMELY SLOW.
::  I have enforced that i <= 100 to make absolutely sure
::  that this arm is only used for shuffling decks and players
::
::  https://dl.acm.org/doi/pdf/10.1145/364520.364540#.pdf
::  -- To shuffle an array a of n elements (indices 0..n-1):
::  for i from n−1 downto 1 do:
::     j ← random integer such that 0 ≤ j ≤ i
::     exchange a[j] and a[i]
::
++  shuffle
  |*  [a=(list) eny=@]
  ^+  a
  =+  r=~(. og eny)
  =+  i=(lent a)
  ?>  (lte i 100)
  |-
  ?:  =(i 0)  a
  =^  j  r
    (rads:r i)
  $(i (dec i), a (into (oust [j 1] a) i (snag j a)))
::
::  gives back [hand rest] where hand is n cards from top of deck, rest is rest
++  draw
  |=  [n=@ud d=pokur-deck]
  [hand=(scag n d) rest=(slag n d)]
--
