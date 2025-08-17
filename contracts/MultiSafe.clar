(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_WALLET_NOT_FOUND (err u101))
(define-constant ERR_INVALID_THRESHOLD (err u102))
(define-constant ERR_DUPLICATE_OWNER (err u103))
(define-constant ERR_TRANSACTION_NOT_FOUND (err u104))
(define-constant ERR_ALREADY_CONFIRMED (err u105))
(define-constant ERR_INSUFFICIENT_CONFIRMATIONS (err u106))
(define-constant ERR_TRANSACTION_EXECUTED (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_INSUFFICIENT_BALANCE (err u109))
(define-constant ERR_SCHEDULED_TRANSACTION_NOT_FOUND (err u110))
(define-constant ERR_TRANSACTION_NOT_READY (err u111))
(define-constant ERR_TRANSACTION_EXPIRED (err u112))
(define-constant ERR_INVALID_DELAY (err u113))
(define-constant ERR_SCHEDULED_TRANSACTION_CANCELLED (err u114))
(define-constant ERR_CANNOT_CANCEL_AFTER_READY (err u115))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u116))
(define-constant ERR_ALREADY_VOTED (err u117))
(define-constant ERR_PROPOSAL_EXPIRED (err u118))
(define-constant ERR_PROPOSAL_NOT_READY (err u119))
(define-constant ERR_PROPOSAL_ALREADY_EXECUTED (err u120))
(define-constant ERR_INSUFFICIENT_VOTES (err u121))
(define-constant ERR_INVALID_PROPOSAL_TYPE (err u122))
(define-constant ERR_INVALID_VOTING_PERIOD (err u123))

(define-data-var wallet-nonce uint u0)
(define-data-var transaction-nonce uint u0)
(define-data-var scheduled-transaction-nonce uint u0)
(define-data-var proposal-nonce uint u0)

(define-map wallets
  { wallet-id: uint }
  {
    owners: (list 10 principal),
    threshold: uint,
    balance: uint,
    created-by: principal,
    created-at: uint
  }
)

(define-map wallet-owners
  { wallet-id: uint, owner: principal }
  { is-owner: bool }
)

(define-map transactions
  { transaction-id: uint }
  {
    wallet-id: uint,
    to: principal,
    amount: uint,
    memo: (string-ascii 100),
    confirmations: uint,
    executed: bool,
    created-by: principal,
    created-at: uint
  }
)

(define-map transaction-confirmations
  { transaction-id: uint, owner: principal }
  { confirmed: bool }
)

(define-map scheduled-transactions
  { scheduled-transaction-id: uint }
  {
    wallet-id: uint,
    to: principal,
    amount: uint,
    memo: (string-ascii 100),
    execution-height: uint,
    expiration-height: uint,
    confirmations: uint,
    executed: bool,
    cancelled: bool,
    created-by: principal,
    created-at: uint
  }
)

(define-map scheduled-transaction-confirmations
  { scheduled-transaction-id: uint, owner: principal }
  { confirmed: bool }
)

(define-map wallet-time-lock-config
  { wallet-id: uint }
  {
    min-delay-blocks: uint,
    max-delay-blocks: uint,
    cancellation-window-blocks: uint,
    auto-execute-enabled: bool
  }
)

(define-map proposals
  { proposal-id: uint }
  {
    wallet-id: uint,
    proposal-type: uint,
    proposal-data: (string-ascii 200),
    new-threshold: (optional uint),
    new-owners: (optional (list 10 principal)),
    new-min-delay: (optional uint),
    new-max-delay: (optional uint),
    voting-period-end: uint,
    yes-votes: uint,
    no-votes: uint,
    executed: bool,
    created-by: principal,
    created-at: uint
  }
)

(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool }
)

(define-public (create-wallet (owners (list 10 principal)) (threshold uint))
  (let
    (
      (wallet-id (+ (var-get wallet-nonce) u1))
      (owners-count (len owners))
    )
    (asserts! (> threshold u0) ERR_INVALID_THRESHOLD)
    (asserts! (<= threshold owners-count) ERR_INVALID_THRESHOLD)
    (asserts! (> owners-count u0) ERR_INVALID_THRESHOLD)
    (asserts! (is-eq (len (remove-duplicates owners)) owners-count) ERR_DUPLICATE_OWNER)
    
    (map-set wallets
      { wallet-id: wallet-id }
      {
        owners: owners,
        threshold: threshold,
        balance: u0,
        created-by: tx-sender,
        created-at: stacks-block-height
      }
    )
    
    (fold set-owner-status-iter owners wallet-id)
    
    (map-set wallet-time-lock-config
      { wallet-id: wallet-id }
      {
        min-delay-blocks: u144,
        max-delay-blocks: u4320,
        cancellation-window-blocks: u144,
        auto-execute-enabled: true
      }
    )
    
    (var-set wallet-nonce wallet-id)
    (ok wallet-id)
  )
)

(define-private (set-owner-status (owner principal) (wallet-id uint))
  (map-set wallet-owners
    { wallet-id: wallet-id, owner: owner }
    { is-owner: true }
  )
)

(define-private (set-owner-status-iter (owner principal) (wallet-id uint))
  (begin
    (set-owner-status owner wallet-id)
    wallet-id
  )
)

(define-private (remove-duplicates (lst (list 10 principal)))
  (fold remove-duplicate-item lst (list))
)

(define-private (remove-duplicate-item (item principal) (acc (list 10 principal)))
  (if (is-none (index-of acc item))
    (unwrap-panic (as-max-len? (append acc item) u10))
    acc
  )
)

(define-public (deposit (wallet-id uint))
  (let
    (
      (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
      (amount (stx-get-balance tx-sender))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { balance: (+ (get balance wallet) amount) })
    )
    (ok amount)
  )
)

(define-public (deposit-amount (wallet-id uint) (amount uint))
  (let
    (
      (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { balance: (+ (get balance wallet) amount) })
    )
    (ok amount)
  )
)

(define-public (propose-transaction (wallet-id uint) (to principal) (amount uint) (memo (string-ascii 100)))
  (let
    (
      (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
      (transaction-id (+ (var-get transaction-nonce) u1))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get balance wallet) amount) ERR_INSUFFICIENT_BALANCE)
    
    (map-set transactions
      { transaction-id: transaction-id }
      {
        wallet-id: wallet-id,
        to: to,
        amount: amount,
        memo: memo,
        confirmations: u1,
        executed: false,
        created-by: tx-sender,
        created-at: stacks-block-height
      }
    )
    
    (map-set transaction-confirmations
      { transaction-id: transaction-id, owner: tx-sender }
      { confirmed: true }
    )
    
    (var-set transaction-nonce transaction-id)
    (ok transaction-id)
  )
)

(define-public (confirm-transaction (transaction-id uint))
  (let
    (
      (transaction (unwrap! (map-get? transactions { transaction-id: transaction-id }) ERR_TRANSACTION_NOT_FOUND))
      (wallet-id (get wallet-id transaction))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed transaction)) ERR_TRANSACTION_EXECUTED)
    (asserts! (is-none (map-get? transaction-confirmations { transaction-id: transaction-id, owner: tx-sender })) ERR_ALREADY_CONFIRMED)
    
    (map-set transaction-confirmations
      { transaction-id: transaction-id, owner: tx-sender }
      { confirmed: true }
    )
    
    (map-set transactions
      { transaction-id: transaction-id }
      (merge transaction { confirmations: (+ (get confirmations transaction) u1) })
    )
    
    (ok true)
  )
)

(define-public (execute-transaction (transaction-id uint))
  (let
    (
      (transaction (unwrap! (map-get? transactions { transaction-id: transaction-id }) ERR_TRANSACTION_NOT_FOUND))
      (wallet (unwrap! (map-get? wallets { wallet-id: (get wallet-id transaction) }) ERR_WALLET_NOT_FOUND))
      (wallet-id (get wallet-id transaction))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed transaction)) ERR_TRANSACTION_EXECUTED)
    (asserts! (>= (get confirmations transaction) (get threshold wallet)) ERR_INSUFFICIENT_CONFIRMATIONS)
    (asserts! (>= (get balance wallet) (get amount transaction)) ERR_INSUFFICIENT_BALANCE)
    
    (try! (as-contract (stx-transfer? (get amount transaction) tx-sender (get to transaction))))
    
    (map-set transactions
      { transaction-id: transaction-id }
      (merge transaction { executed: true })
    )
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { balance: (- (get balance wallet) (get amount transaction)) })
    )
    
    (ok true)
  )
)

(define-public (configure-wallet-timelock (wallet-id uint) (min-delay-blocks uint) (max-delay-blocks uint) (cancellation-window-blocks uint) (auto-execute-enabled bool))
  (let
    (
      (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> min-delay-blocks u0) ERR_INVALID_DELAY)
    (asserts! (>= max-delay-blocks min-delay-blocks) ERR_INVALID_DELAY)
    (asserts! (> cancellation-window-blocks u0) ERR_INVALID_DELAY)
    
    (map-set wallet-time-lock-config
      { wallet-id: wallet-id }
      {
        min-delay-blocks: min-delay-blocks,
        max-delay-blocks: max-delay-blocks,
        cancellation-window-blocks: cancellation-window-blocks,
        auto-execute-enabled: auto-execute-enabled
      }
    )
    (ok true)
  )
)

(define-public (schedule-transaction (wallet-id uint) (to principal) (amount uint) (memo (string-ascii 100)) (delay-blocks uint))
  (let
    (
      (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
      (timelock-config (unwrap! (map-get? wallet-time-lock-config { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
      (scheduled-transaction-id (+ (var-get scheduled-transaction-nonce) u1))
      (execution-height (+ stacks-block-height delay-blocks))
      (expiration-height (+ execution-height (get cancellation-window-blocks timelock-config)))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get balance wallet) amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= delay-blocks (get min-delay-blocks timelock-config)) ERR_INVALID_DELAY)
    (asserts! (<= delay-blocks (get max-delay-blocks timelock-config)) ERR_INVALID_DELAY)
    
    (map-set scheduled-transactions
      { scheduled-transaction-id: scheduled-transaction-id }
      {
        wallet-id: wallet-id,
        to: to,
        amount: amount,
        memo: memo,
        execution-height: execution-height,
        expiration-height: expiration-height,
        confirmations: u1,
        executed: false,
        cancelled: false,
        created-by: tx-sender,
        created-at: stacks-block-height
      }
    )
    
    (map-set scheduled-transaction-confirmations
      { scheduled-transaction-id: scheduled-transaction-id, owner: tx-sender }
      { confirmed: true }
    )
    
    (var-set scheduled-transaction-nonce scheduled-transaction-id)
    (ok scheduled-transaction-id)
  )
)

(define-public (confirm-scheduled-transaction (scheduled-transaction-id uint))
  (let
    (
      (scheduled-transaction (unwrap! (map-get? scheduled-transactions { scheduled-transaction-id: scheduled-transaction-id }) ERR_SCHEDULED_TRANSACTION_NOT_FOUND))
      (wallet-id (get wallet-id scheduled-transaction))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed scheduled-transaction)) ERR_TRANSACTION_EXECUTED)
    (asserts! (not (get cancelled scheduled-transaction)) ERR_SCHEDULED_TRANSACTION_CANCELLED)
    (asserts! (is-none (map-get? scheduled-transaction-confirmations { scheduled-transaction-id: scheduled-transaction-id, owner: tx-sender })) ERR_ALREADY_CONFIRMED)
    
    (map-set scheduled-transaction-confirmations
      { scheduled-transaction-id: scheduled-transaction-id, owner: tx-sender }
      { confirmed: true }
    )
    
    (map-set scheduled-transactions
      { scheduled-transaction-id: scheduled-transaction-id }
      (merge scheduled-transaction { confirmations: (+ (get confirmations scheduled-transaction) u1) })
    )
    
    (ok true)
  )
)

(define-public (cancel-scheduled-transaction (scheduled-transaction-id uint))
  (let
    (
      (scheduled-transaction (unwrap! (map-get? scheduled-transactions { scheduled-transaction-id: scheduled-transaction-id }) ERR_SCHEDULED_TRANSACTION_NOT_FOUND))
      (wallet-id (get wallet-id scheduled-transaction))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed scheduled-transaction)) ERR_TRANSACTION_EXECUTED)
    (asserts! (not (get cancelled scheduled-transaction)) ERR_SCHEDULED_TRANSACTION_CANCELLED)
    (asserts! (< stacks-block-height (get execution-height scheduled-transaction)) ERR_CANNOT_CANCEL_AFTER_READY)
    
    (map-set scheduled-transactions
      { scheduled-transaction-id: scheduled-transaction-id }
      (merge scheduled-transaction { cancelled: true })
    )
    
    (ok true)
  )
)

(define-public (execute-scheduled-transaction (scheduled-transaction-id uint))
  (let
    (
      (scheduled-transaction (unwrap! (map-get? scheduled-transactions { scheduled-transaction-id: scheduled-transaction-id }) ERR_SCHEDULED_TRANSACTION_NOT_FOUND))
      (wallet (unwrap! (map-get? wallets { wallet-id: (get wallet-id scheduled-transaction) }) ERR_WALLET_NOT_FOUND))
      (wallet-id (get wallet-id scheduled-transaction))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed scheduled-transaction)) ERR_TRANSACTION_EXECUTED)
    (asserts! (not (get cancelled scheduled-transaction)) ERR_SCHEDULED_TRANSACTION_CANCELLED)
    (asserts! (>= stacks-block-height (get execution-height scheduled-transaction)) ERR_TRANSACTION_NOT_READY)
    (asserts! (< stacks-block-height (get expiration-height scheduled-transaction)) ERR_TRANSACTION_EXPIRED)
    (asserts! (>= (get confirmations scheduled-transaction) (get threshold wallet)) ERR_INSUFFICIENT_CONFIRMATIONS)
    (asserts! (>= (get balance wallet) (get amount scheduled-transaction)) ERR_INSUFFICIENT_BALANCE)
    
    (try! (as-contract (stx-transfer? (get amount scheduled-transaction) tx-sender (get to scheduled-transaction))))
    
    (map-set scheduled-transactions
      { scheduled-transaction-id: scheduled-transaction-id }
      (merge scheduled-transaction { executed: true })
    )
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { balance: (- (get balance wallet) (get amount scheduled-transaction)) })
    )
    
    (ok true)
  )
)

(define-read-only (get-wallet (wallet-id uint))
  (map-get? wallets { wallet-id: wallet-id })
)

(define-read-only (get-transaction (transaction-id uint))
  (map-get? transactions { transaction-id: transaction-id })
)

(define-read-only (is-wallet-owner (wallet-id uint) (owner principal))
  (default-to false (get is-owner (map-get? wallet-owners { wallet-id: wallet-id, owner: owner })))
)

(define-read-only (has-confirmed-transaction (transaction-id uint) (owner principal))
  (default-to false (get confirmed (map-get? transaction-confirmations { transaction-id: transaction-id, owner: owner })))
)

(define-read-only (get-wallet-count)
  (var-get wallet-nonce)
)

(define-read-only (get-transaction-count)
  (var-get transaction-nonce)
)

(define-read-only (get-wallet-balance (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (some (get balance wallet))
    none
  )
)

(define-read-only (get-scheduled-transaction (scheduled-transaction-id uint))
  (map-get? scheduled-transactions { scheduled-transaction-id: scheduled-transaction-id })
)

(define-read-only (get-wallet-timelock-config (wallet-id uint))
  (map-get? wallet-time-lock-config { wallet-id: wallet-id })
)

(define-read-only (has-confirmed-scheduled-transaction (scheduled-transaction-id uint) (owner principal))
  (default-to false (get confirmed (map-get? scheduled-transaction-confirmations { scheduled-transaction-id: scheduled-transaction-id, owner: owner })))
)

(define-read-only (get-scheduled-transaction-count)
  (var-get scheduled-transaction-nonce)
)

(define-read-only (is-scheduled-transaction-ready (scheduled-transaction-id uint))
  (match (map-get? scheduled-transactions { scheduled-transaction-id: scheduled-transaction-id })
    scheduled-transaction 
      (and 
        (>= stacks-block-height (get execution-height scheduled-transaction))
        (< stacks-block-height (get expiration-height scheduled-transaction))
        (not (get executed scheduled-transaction))
        (not (get cancelled scheduled-transaction))
      )
    false
  )
)

(define-read-only (is-scheduled-transaction-expired (scheduled-transaction-id uint))
  (match (map-get? scheduled-transactions { scheduled-transaction-id: scheduled-transaction-id })
    scheduled-transaction (>= stacks-block-height (get expiration-height scheduled-transaction))
    false
  )
)

(define-public (create-proposal (wallet-id uint) (proposal-type uint) (proposal-data (string-ascii 200)) (voting-period-blocks uint) (new-threshold (optional uint)) (new-owners (optional (list 10 principal))) (new-min-delay (optional uint)) (new-max-delay (optional uint)))
  (let
    (
      (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
      (proposal-id (+ (var-get proposal-nonce) u1))
      (voting-end (+ stacks-block-height voting-period-blocks))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= proposal-type u1) (<= proposal-type u3)) ERR_INVALID_PROPOSAL_TYPE)
    (asserts! (> voting-period-blocks u0) ERR_INVALID_VOTING_PERIOD)
    (asserts! (<= voting-period-blocks u10080) ERR_INVALID_VOTING_PERIOD)
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        wallet-id: wallet-id,
        proposal-type: proposal-type,
        proposal-data: proposal-data,
        new-threshold: new-threshold,
        new-owners: new-owners,
        new-min-delay: new-min-delay,
        new-max-delay: new-max-delay,
        voting-period-end: voting-end,
        yes-votes: u0,
        no-votes: u0,
        executed: false,
        created-by: tx-sender,
        created-at: stacks-block-height
      }
    )
    
    (var-set proposal-nonce proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
      (wallet-id (get wallet-id proposal))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (< stacks-block-height (get voting-period-end proposal)) ERR_PROPOSAL_EXPIRED)
    (asserts! (not (get executed proposal)) ERR_PROPOSAL_ALREADY_EXECUTED)
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: tx-sender })) ERR_ALREADY_VOTED)
    
    (map-set proposal-votes
      { proposal-id: proposal-id, voter: tx-sender }
      { vote: vote }
    )
    
    (map-set proposals
      { proposal-id: proposal-id }
      (if vote
        (merge proposal { yes-votes: (+ (get yes-votes proposal) u1) })
        (merge proposal { no-votes: (+ (get no-votes proposal) u1) })
      )
    )
    
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
      (wallet (unwrap! (map-get? wallets { wallet-id: (get wallet-id proposal) }) ERR_WALLET_NOT_FOUND))
      (wallet-id (get wallet-id proposal))
      (owners-count (len (get owners wallet)))
      (required-votes (+ (/ owners-count u2) u1))
    )
    (asserts! (is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (>= stacks-block-height (get voting-period-end proposal)) ERR_PROPOSAL_NOT_READY)
    (asserts! (not (get executed proposal)) ERR_PROPOSAL_ALREADY_EXECUTED)
    (asserts! (>= (get yes-votes proposal) required-votes) ERR_INSUFFICIENT_VOTES)
    (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERR_INSUFFICIENT_VOTES)
    
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal { executed: true })
    )
    
    (if (is-eq (get proposal-type proposal) u1)
      (execute-threshold-change-proposal wallet-id proposal)
      (if (is-eq (get proposal-type proposal) u2)
        (execute-owners-change-proposal wallet-id proposal)
        (execute-timelock-change-proposal wallet-id proposal)
      )
    )
  )
)

(define-private (execute-threshold-change-proposal (wallet-id uint) (proposal { wallet-id: uint, proposal-type: uint, proposal-data: (string-ascii 200), new-threshold: (optional uint), new-owners: (optional (list 10 principal)), new-min-delay: (optional uint), new-max-delay: (optional uint), voting-period-end: uint, yes-votes: uint, no-votes: uint, executed: bool, created-by: principal, created-at: uint }))
  (let
    (
      (wallet (unwrap-panic (map-get? wallets { wallet-id: wallet-id })))
      (new-threshold-value (unwrap-panic (get new-threshold proposal)))
    )
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { threshold: new-threshold-value })
    )
    (ok true)
  )
)

(define-private (execute-owners-change-proposal (wallet-id uint) (proposal { wallet-id: uint, proposal-type: uint, proposal-data: (string-ascii 200), new-threshold: (optional uint), new-owners: (optional (list 10 principal)), new-min-delay: (optional uint), new-max-delay: (optional uint), voting-period-end: uint, yes-votes: uint, no-votes: uint, executed: bool, created-by: principal, created-at: uint }))
  (let
    (
      (wallet (unwrap-panic (map-get? wallets { wallet-id: wallet-id })))
      (new-owners-list (unwrap-panic (get new-owners proposal)))
    )
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { owners: new-owners-list })
    )
    (fold set-owner-status-iter new-owners-list wallet-id)
    (ok true)
  )
)

(define-private (execute-timelock-change-proposal (wallet-id uint) (proposal { wallet-id: uint, proposal-type: uint, proposal-data: (string-ascii 200), new-threshold: (optional uint), new-owners: (optional (list 10 principal)), new-min-delay: (optional uint), new-max-delay: (optional uint), voting-period-end: uint, yes-votes: uint, no-votes: uint, executed: bool, created-by: principal, created-at: uint }))
  (let
    (
      (current-config (unwrap-panic (map-get? wallet-time-lock-config { wallet-id: wallet-id })))
      (new-min-delay-value (unwrap-panic (get new-min-delay proposal)))
      (new-max-delay-value (unwrap-panic (get new-max-delay proposal)))
    )
    (map-set wallet-time-lock-config
      { wallet-id: wallet-id }
      (merge current-config { min-delay-blocks: new-min-delay-value, max-delay-blocks: new-max-delay-value })
    )
    (ok true)
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-proposal-count)
  (var-get proposal-nonce)
)

(define-read-only (has-voted-on-proposal (proposal-id uint) (voter principal))
  (is-some (map-get? proposal-votes { proposal-id: proposal-id, voter: voter }))
)

(define-read-only (get-voter-choice (proposal-id uint) (voter principal))
  (match (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
    vote-data (some (get vote vote-data))
    none
  )
)

(define-read-only (is-proposal-ready-for-execution (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal
      (let
        (
          (wallet (unwrap-panic (map-get? wallets { wallet-id: (get wallet-id proposal) })))
          (owners-count (len (get owners wallet)))
          (required-votes (+ (/ owners-count u2) u1))
        )
        (and
          (>= stacks-block-height (get voting-period-end proposal))
          (not (get executed proposal))
          (>= (get yes-votes proposal) required-votes)
          (> (get yes-votes proposal) (get no-votes proposal))
        )
      )
    false
  )
)

(define-read-only (get-proposal-vote-status (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal
      (let
        (
          (wallet (unwrap-panic (map-get? wallets { wallet-id: (get wallet-id proposal) })))
          (owners-count (len (get owners wallet)))
          (required-votes (+ (/ owners-count u2) u1))
        )
        (some {
          yes-votes: (get yes-votes proposal),
          no-votes: (get no-votes proposal),
          required-votes: required-votes,
          total-owners: owners-count,
          voting-ends: (get voting-period-end proposal),
          can-execute: (and
            (>= stacks-block-height (get voting-period-end proposal))
            (not (get executed proposal))
            (>= (get yes-votes proposal) required-votes)
            (> (get yes-votes proposal) (get no-votes proposal))
          )
        })
      )
    none
  )
)


