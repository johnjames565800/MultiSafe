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

(define-data-var wallet-nonce uint u0)
(define-data-var transaction-nonce uint u0)

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
    
    ;; (map set-owner-status owners wallet-id)
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