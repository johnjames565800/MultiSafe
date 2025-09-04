;; Emergency Recovery System for MultiSafe Wallets
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_WALLET_NOT_FOUND (err u201))
(define-constant ERR_EMERGENCY_NOT_FOUND (err u202))
(define-constant ERR_EMERGENCY_ALREADY_EXECUTED (err u203))
(define-constant ERR_EMERGENCY_EXPIRED (err u204))
(define-constant ERR_EMERGENCY_NOT_READY (err u205))
(define-constant ERR_INVALID_RECOVERY_TYPE (err u206))
(define-constant ERR_INSUFFICIENT_EMERGENCY_VOTES (err u207))
(define-constant ERR_ALREADY_VOTED_EMERGENCY (err u208))
(define-constant ERR_EMERGENCY_LOCKOUT_ACTIVE (err u209))
(define-constant ERR_INVALID_EMERGENCY_DURATION (err u210))
(define-data-var emergency-proposal-nonce uint u0)

;; Emergency Recovery Proposals
(define-map emergency-proposals
  { emergency-id: uint }
  {
    wallet-id: uint,
    recovery-type: uint,
    target-address: (optional principal),
    recovery-amount: (optional uint),
    new-emergency-owners: (optional (list 5 principal)),
    emergency-reason: (string-ascii 200),
    emergency-threshold: uint,
    activation-height: uint,
    expiration-height: uint,
    emergency-votes: uint,
    executed: bool,
    created-by: principal,
    created-at: uint
  }
)

;; Emergency Votes
(define-map emergency-votes
  { emergency-id: uint, voter: principal }
  { voted: bool, vote-height: uint }
)

;; Emergency Configuration per wallet
(define-map emergency-config
  { wallet-id: uint }
  {
    emergency-threshold-override: uint,
    emergency-delay-blocks: uint,
    emergency-expiry-blocks: uint,
    recovery-lockout-blocks: uint,
    last-emergency-execution: (optional uint),
    emergency-enabled: bool
  }
)

;; Configure emergency settings for a wallet
(define-public (configure-emergency-settings (wallet-id uint) (emergency-threshold-override uint) (emergency-delay-blocks uint) (emergency-expiry-blocks uint) (recovery-lockout-blocks uint))
  (begin
    (asserts! (contract-call? .MultiSafe is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> emergency-threshold-override u0) ERR_INVALID_RECOVERY_TYPE)
    (asserts! (and (> emergency-delay-blocks u0) (<= emergency-delay-blocks u1008)) ERR_INVALID_EMERGENCY_DURATION)
    (asserts! (and (> emergency-expiry-blocks emergency-delay-blocks) (<= emergency-expiry-blocks u4320)) ERR_INVALID_EMERGENCY_DURATION)
    (map-set emergency-config { wallet-id: wallet-id } { emergency-threshold-override: emergency-threshold-override, emergency-delay-blocks: emergency-delay-blocks, emergency-expiry-blocks: emergency-expiry-blocks, recovery-lockout-blocks: recovery-lockout-blocks, last-emergency-execution: none, emergency-enabled: true })
    (ok true)
  )
)

;; Propose an emergency recovery action
(define-public (propose-emergency-recovery
    (wallet-id uint)
    (recovery-type uint)
    (target-address (optional principal))
    (recovery-amount (optional uint))
    (new-emergency-owners (optional (list 5 principal)))
    (emergency-reason (string-ascii 200)))
  (let (
    (emergency-id (+ (var-get emergency-proposal-nonce) u1))
    (config (unwrap! (map-get? emergency-config { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND))
    (activation-height (+ stacks-block-height (get emergency-delay-blocks config)))
    (expiration-height (+ activation-height (get emergency-expiry-blocks config)))
    (last-execution (get last-emergency-execution config))
  )
    (asserts! (contract-call? .MultiSafe is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get emergency-enabled config) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= recovery-type u1) (<= recovery-type u3)) ERR_INVALID_RECOVERY_TYPE)
    
    ;; Check lockout period if there was a previous emergency execution
    (match last-execution
      last-height 
        (asserts! (>= stacks-block-height (+ last-height (get recovery-lockout-blocks config))) ERR_EMERGENCY_LOCKOUT_ACTIVE)
      true
    )
    
    (map-set emergency-proposals
      { emergency-id: emergency-id }
      {
        wallet-id: wallet-id,
        recovery-type: recovery-type,
        target-address: target-address,
        recovery-amount: recovery-amount,
        new-emergency-owners: new-emergency-owners,
        emergency-reason: emergency-reason,
        emergency-threshold: (get emergency-threshold-override config),
        activation-height: activation-height,
        expiration-height: expiration-height,
        emergency-votes: u1,
        executed: false,
        created-by: tx-sender,
        created-at: stacks-block-height
      }
    )
    
    (map-set emergency-votes
      { emergency-id: emergency-id, voter: tx-sender }
      { voted: true, vote-height: stacks-block-height }
    )
    
    (var-set emergency-proposal-nonce emergency-id)
    (ok emergency-id)
  )
)

;; Vote on emergency recovery proposal
(define-public (vote-emergency-recovery (emergency-id uint))
  (let (
    (proposal (unwrap! (map-get? emergency-proposals { emergency-id: emergency-id }) ERR_EMERGENCY_NOT_FOUND))
    (wallet-id (get wallet-id proposal))
  )
    (asserts! (contract-call? .MultiSafe is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed proposal)) ERR_EMERGENCY_ALREADY_EXECUTED)
    (asserts! (< stacks-block-height (get expiration-height proposal)) ERR_EMERGENCY_EXPIRED)
    (asserts! (is-none (map-get? emergency-votes { emergency-id: emergency-id, voter: tx-sender })) ERR_ALREADY_VOTED_EMERGENCY)
    
    (map-set emergency-votes
      { emergency-id: emergency-id, voter: tx-sender }
      { voted: true, vote-height: stacks-block-height }
    )
    
    (map-set emergency-proposals
      { emergency-id: emergency-id }
      (merge proposal { emergency-votes: (+ (get emergency-votes proposal) u1) })
    )
    
    (ok true)
  )
)

;; Execute emergency recovery proposal
(define-public (execute-emergency-recovery (emergency-id uint))
  (let ((proposal (unwrap! (map-get? emergency-proposals { emergency-id: emergency-id }) ERR_EMERGENCY_NOT_FOUND)) (wallet-id (get wallet-id proposal)) (config (unwrap! (map-get? emergency-config { wallet-id: wallet-id }) ERR_WALLET_NOT_FOUND)))
    (asserts! (contract-call? .MultiSafe is-wallet-owner wallet-id tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get executed proposal)) ERR_EMERGENCY_ALREADY_EXECUTED)
    (asserts! (>= stacks-block-height (get activation-height proposal)) ERR_EMERGENCY_NOT_READY)
    (asserts! (< stacks-block-height (get expiration-height proposal)) ERR_EMERGENCY_EXPIRED)
    (asserts! (>= (get emergency-votes proposal) (get emergency-threshold proposal)) ERR_INSUFFICIENT_EMERGENCY_VOTES)
    (map-set emergency-proposals { emergency-id: emergency-id } (merge proposal { executed: true }))
    (map-set emergency-config { wallet-id: wallet-id } (merge config { last-emergency-execution: (some stacks-block-height) }))
    (if (is-eq (get recovery-type proposal) u3) (map-set emergency-config { wallet-id: wallet-id } (merge config { emergency-enabled: false })) true)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-emergency-proposal (emergency-id uint)) (map-get? emergency-proposals { emergency-id: emergency-id }))
(define-read-only (get-emergency-config (wallet-id uint)) (map-get? emergency-config { wallet-id: wallet-id }))
(define-read-only (has-voted-emergency (emergency-id uint) (voter principal)) (is-some (map-get? emergency-votes { emergency-id: emergency-id, voter: voter })))
(define-read-only (get-emergency-proposal-count) (var-get emergency-proposal-nonce))
(define-read-only (is-emergency-ready (emergency-id uint)) (match (map-get? emergency-proposals { emergency-id: emergency-id }) proposal (and (>= stacks-block-height (get activation-height proposal)) (< stacks-block-height (get expiration-height proposal)) (not (get executed proposal)) (>= (get emergency-votes proposal) (get emergency-threshold proposal))) false))
(define-read-only (get-emergency-vote-status (emergency-id uint)) (match (map-get? emergency-proposals { emergency-id: emergency-id }) proposal (some { current-votes: (get emergency-votes proposal), required-votes: (get emergency-threshold proposal), activation-height: (get activation-height proposal), expiration-height: (get expiration-height proposal), can-execute: (and (>= stacks-block-height (get activation-height proposal)) (< stacks-block-height (get expiration-height proposal)) (not (get executed proposal)) (>= (get emergency-votes proposal) (get emergency-threshold proposal))) }) none))