/-  eng=zig-engine, uqbar=zig-uqbar
/+  smart=zig-sys-smart
|%
+$  token-metadata  token-metadata:eng
+$  token-account  token-account:eng
+$  nft-metadata    nft-metadata:eng
+$  nft             nft:eng
::
+$  signature   [p=@ux q=ship r=life]
::
::  for app-generated transactions to be notified of their txn results
::
+$  origin  (unit (pair term wire))
::
::  for choosing which address to share if asked, if any
::
+$  share-prefs
  $~  [%any ~]  ::  default
  $%  [%one =address:smart]  ::  specify which address we want to share
      [%any ~]               ::  just grab any one address in our wallet
      [%none ~]              ::  don't share uqbar addresses with anyone
  ==
::
::  book: the primary map of assets that we track
::  supports fungibles and NFTs
::
+$  book  (map id:smart asset)
+$  asset
  $%  [%token town=@ux contract=id:smart metadata=id:smart token-account]
      [%nft town=@ux contract=id:smart metadata=id:smart nft]
      [%unknown town=@ux contract=id:smart *]
  ==
::
+$  metadata-store  (map id:smart asset-metadata)
+$  asset-metadata
  $%  [%token town=@ux contract=id:smart token-metadata]
      [%nft town=@ux contract=id:smart nft-metadata]
  ==
::
::  keyed by message hash
::
+$  signed-message-store
  (map @ux [=typed-message:smart =sig:smart])
::
+$  unfinished-transaction-store
  (map @ux unfinished-transaction)
::
+$  unfinished-transaction
  [=origin =transaction:smart action=supported-actions output=(unit output:eng)]
::
::  inner maps keyed by transaction hash
::  transaction-store holds all finished transactions,
::  both ones sent by the address, and ones containing
::  outputs which correspond to assets belong to that address.
+$  transaction-store
  %+  map  address:smart
  (map @ux finished-transaction)
::
+$  finished-transaction
  [=origin batch=@ux =transaction:smart action=supported-actions =output:eng]
::
+$  pending-store
  %+  map  address:smart
  (map @ux [=origin =transaction:smart action=supported-actions])
::
+$  transaction-status-code
  $?  %100  ::  100: transaction pending in wallet
      %101  ::  101: transaction submitted from wallet to sequencer
      %102  ::  102: transaction received by sequencer
      %103  ::  103: failure: transaction rejected by sequencer
      ::
      ::  200-class refers to codes that come from a completed transaction
      ::  that sequencer has given us a receipt for,
      ::  informed by status codes in smart.hoon
      ::
      ::  300-class are equivalent, but the transaction has been officially
      ::  included in a batch.
      ::
      %200  %300 ::  successfully performed
      %201  %301 ::  bad signature
      %202  %302 ::  incorrect nonce
      %203  %303 ::  lack zigs to fulfill budget
      %204  %304 ::  couldn't find contract
      %205  %305 ::  data was under contract ID
      %206  %306 ::  crash in contract execution
      %207  %307 ::  validation of diff failed
      %208  %308 ::  ran out of gas while executing
      %209  %309 ::  dedicated burn transaction failed
      ::
      ::  error code %BYZANTINE occurs when the result of a transaction
      ::  indicates to us that the sequencer is byzantine.
      ::
      %'BYZANTINE'
  ==
::
::  noun type that comes from wallet scries, used thru uqbar.hoon
::
+$  wallet-update
  $@  ~
  $%  [%asset asset]
      [%metadata asset-metadata]
      [%account =caller:smart]  ::  tuple of [address nonce zigs-account]
      [%addresses saved=(set address:smart)]
      [%signed-message =origin =typed-message:smart =sig:smart]
      $:  %unfinished-transaction
          =origin
          =transaction:smart
          action=supported-actions
      ==
      ::  poked back to origin after sequencer optimistically processes
      [%sequencer-receipt =origin =hash:smart sequencer-receipt:uqbar]
      ::  poked back to origin when transaction is included in batch
      [%finished-transaction finished-transaction]
  ==
::
::  sent to web interface
::
+$  wallet-frontend-update
  $%  [%new-book tokens=(map pub=id:smart =book)]
      [%new-metadata metadata=metadata-store]
      [%tx-status hash=@ux =transaction:smart action=supported-actions]
      $:  %finished-tx
          hash=@ux
          finished-transaction
      ==
  ==
::
::  received from web interface
::
+$  wallet-poke
  $%  [%import-seed mnemonic=@t password=@t nick=@t]
      [%generate-hot-wallet password=@t nick=@t]
      [%store-hot-wallet nick=@t address=@ux priv=@t seed=@t]
      [%derive-new-address hdpath=tape nick=@t]
      [%delete-address address=@ux]
      [%edit-nickname address=@ux nick=@t]
      [%sign-typed-message =origin from=address:smart domain=id:smart type=json msg=*]
      [%add-tracked-address address=@ux nick=@t]
      [%set-share-prefs =share-prefs]
      ::  testing and internal
      [%set-nonce address=@ux town=@ux new=@ud]
      [%approve-origin (pair term wire) gas=[rate=@ud bud=@ud]]
      [%remove-origin (pair term wire)]
      ::
      ::  TX submit pokes
      ::
      ::  sign a pending transaction from an attached hardware wallet
      $:  %submit-signed
          from=address:smart
          hash=@
          eth-hash=@
          sig=[v=@ r=@ s=@]
          gas=[rate=@ud bud=@ud]
      ==
      ::  sign a pending transaction from this wallet
      $:  %submit
          from=address:smart
          hash=@
          gas=[rate=@ud bud=@ud]
      ==
      ::  remove a pending transaction without signing
      $:  %delete-pending
          from=address:smart
          hash=@
      ==
      ::
      $:  %transaction
          =origin
          from=address:smart
          contract=id:smart
          town=@ux
          action=supported-actions
      ==
      $:  %unsigned-transaction
          =origin
          contract=id:smart
          town=@ux
          action=$%([%noun [%validate *]] [%text @t])
      ==
      ::
      $:  %transaction-to-ship
          =origin
          from=address:smart
          contract=id:smart
          town=@ux
          =ship
          action=supported-actions  ::  address field will be ignored
      ==
  ==
::
+$  supported-actions
  $%  [%give to=address:smart amount=@ud item=id:smart]
      [%give-nft to=address:smart item=id:smart]
      [%text @t]
      [%noun *]
  ==
::
+$  state-2
  $:  %2
      ::  wallet holds a single seed at once
      ::  address-index notes where we are in derivation path
      seed=[mnem=@t pass=@t address-index=@ud]
      ::  many keys can be derived or imported
      ::  if the private key is ~, that means it's a hardware wallet import
      keys=(map address:smart [priv=(unit @ux) nick=@t])
      ::  we track the nonce of each address we're handling
      ::  TODO: introduce a poke to check nonce from chain and re-align
      nonces=(map address:smart (map town=@ux nonce=@ud))
      ::  signatures tracks any signed calls we've made
      =signed-message-store
      ::  tokens tracked for each address we're handling
      tokens=(map address:smart =book)
      ::  metadata for tokens we track
      =metadata-store
      ::  origins we automatically sign and approve txns from
      approved-origins=(map (pair term wire) [rate=@ud bud=@ud])
      ::  transactions we've sent that haven't been finalized by sequencer
      =unfinished-transaction-store
      ::  finished transactions we've sent
      =transaction-store
      ::  transactions we've been asked to sign, keyed by hash
      =pending-store
  ==
+$  state-3
  $:  %3
      ::  wallet holds a single seed at once
      ::  address-index notes where we are in derivation path
      seed=[mnem=@t pass=@t address-index=@ud]
      ::  many keys can be derived or imported
      ::  if the private key is ~, that means it's a hardware wallet import
      keys=(map address:smart [priv=(unit @ux) nick=@t])
      =share-prefs
      ::  we track the nonce of each address we're handling
      ::  TODO: introduce a mechanism to check nonce from chain and re-align
      nonces=(map address:smart (map town=@ux nonce=@ud))
      ::  signatures tracks any signed calls we've made
      =signed-message-store
      ::  tokens tracked for each address we're handling
      tokens=(map address:smart =book)
      ::  metadata for tokens we track
      =metadata-store
      ::  origins we automatically sign and approve txns from
      approved-origins=(map (pair term wire) [rate=@ud bud=@ud])
      ::  transactions we've sent that haven't been finalized by sequencer
      =unfinished-transaction-store
      ::  finished transactions we've sent
      =transaction-store
      ::  transactions we've been asked to sign, keyed by hash
      =pending-store
  ==
--
