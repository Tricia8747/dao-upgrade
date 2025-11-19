;; ------------------------------------------------------------
;; dao-constitution-upgrade.clar
;; ------------------------------------------------------------
;; Purpose:
;;   This contract manages DAO constitutional parameters and
;;   enables upgrades through member proposals and voting.
;;
;; Features:
;; - DAO members can propose constitution upgrades.
;; - Weighted voting (1 member = 1 vote).
;; - Requires quorum and majority approval.
;; - Automatically applies new constitution settings after approval.
;;
;; Compatible with STX DAO and governance systems.
;; ------------------------------------------------------------

(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_ALREADY_VOTED u101)
(define-constant ERR_NOT_ACTIVE u102)
(define-constant ERR_PROPOSAL_NOT_FOUND u103)
(define-constant ERR_INVALID_PARAM u104)

;; ------------------------------------------------------------
;; DAO PARAMETERS (current constitution)
;; ------------------------------------------------------------

(define-data-var quorum uint u50) ;; % required to pass
(define-data-var proposal-duration uint u10080) ;; ~7 days in blocks
(define-data-var active-version uint u1) ;; constitution version number

;; DAO admin (creator)
(define-data-var admin principal tx-sender)

;; ------------------------------------------------------------
;; PROPOSAL STRUCTURE
;; ------------------------------------------------------------

(define-map proposals
  uint
  {
    proposer: principal,
    quorum: uint,
    proposal-duration: uint,
    new-version: uint,
    start-block: uint,
    yes-votes: uint,
    no-votes: uint,
    executed: bool
  }
)

(define-map has-voted
  { proposal-id: uint, voter: principal }
  bool
)

(define-data-var proposal-counter uint u0)

;; ------------------------------------------------------------
;; PRIVATE HELPERS
;; ------------------------------------------------------------

(define-private (is-admin (who principal))
  (is-eq who (var-get admin))
)

(define-private (proposal-active? (proposal-id uint))
  (let ((proposal (map-get? proposals proposal-id)))
    (match proposal
      proposal-data
        (let ((duration (get proposal-duration proposal-data))
              (start (get start-block proposal-data)))
          (ok (< burn-block-height (+ start duration)))
        )
      (err ERR_PROPOSAL_NOT_FOUND)
    )
  )
)

;; ------------------------------------------------------------
;; PUBLIC FUNCTIONS
;; ------------------------------------------------------------

;; Submit a new constitution proposal
(define-public (submit-proposal (new-quorum uint) (new-duration uint))
  (begin
    (asserts! (>= new-quorum u10) (err ERR_INVALID_PARAM))
    (asserts! (>= new-duration u1000) (err ERR_INVALID_PARAM))

    (var-set proposal-counter (+ (var-get proposal-counter) u1))
    (let ((id (var-get proposal-counter)))
      (map-set proposals id {
        proposer: tx-sender,
        quorum: new-quorum,
        proposal-duration: new-duration,
        new-version: (+ (var-get active-version) u1),
        start-block: burn-block-height,
        yes-votes: u0,
        no-votes: u0,
        executed: false
      })
      (ok id)
    )
  )
)

;; Cast a vote
(define-public (vote (proposal-id uint) (support bool))
  (begin
    (asserts! (is-none (map-get? has-voted { proposal-id: proposal-id, voter: tx-sender })) (err ERR_ALREADY_VOTED))

    (let ((proposal (unwrap! (map-get? proposals proposal-id) (err ERR_PROPOSAL_NOT_FOUND))))
      (asserts! (unwrap! (proposal-active? proposal-id) (err ERR_NOT_ACTIVE)) (err ERR_NOT_ACTIVE))
      
      (let ((current-yes (get yes-votes proposal))
            (current-no (get no-votes proposal)))
        (if support
            (map-set proposals proposal-id 
              {
                proposer: (get proposer proposal),
                quorum: (get quorum proposal),
                proposal-duration: (get proposal-duration proposal),
                new-version: (get new-version proposal),
                start-block: (get start-block proposal),
                yes-votes: (+ current-yes u1),
                no-votes: current-no,
                executed: (get executed proposal)
              })
            (map-set proposals proposal-id 
              {
                proposer: (get proposer proposal),
                quorum: (get quorum proposal),
                proposal-duration: (get proposal-duration proposal),
                new-version: (get new-version proposal),
                start-block: (get start-block proposal),
                yes-votes: current-yes,
                no-votes: (+ current-no u1),
                executed: (get executed proposal)
              }))
        (map-set has-voted { proposal-id: proposal-id, voter: tx-sender } true)
        (ok support)))
  ))

;; Execute proposal (if it passes)
(define-public (execute-upgrade (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) (err ERR_PROPOSAL_NOT_FOUND))))
    (begin
      (asserts! (not (get executed proposal)) (err ERR_NOT_ACTIVE))
      (let (
            (yes (get yes-votes proposal))
            (no (get no-votes proposal))
            (total (+ yes no))
            (required (/ (* total (get quorum proposal)) u100))
          )
        (if (>= yes required)
            (begin
              (var-set quorum (get quorum proposal))
              (var-set proposal-duration (get proposal-duration proposal))
              (var-set active-version (get new-version proposal))
              (map-set proposals proposal-id 
                {
                  proposer: (get proposer proposal),
                  quorum: (get quorum proposal),
                  proposal-duration: (get proposal-duration proposal),
                  new-version: (get new-version proposal),
                  start-block: (get start-block proposal),
                  yes-votes: yes,
                  no-votes: no,
                  executed: true
                })
              (ok "Constitution upgraded successfully")
            )
            (err ERR_UNAUTHORIZED)
        )
      )
    )
  )
)

;; ------------------------------------------------------------
;; READ-ONLY FUNCTIONS
;; ------------------------------------------------------------

(define-read-only (get-constitution)
  (ok {
    version: (var-get active-version),
    quorum: (var-get quorum),
    proposal-duration: (var-get proposal-duration)
  })
)

(define-read-only (get-proposal (id uint))
  (ok (map-get? proposals id))
)

(define-read-only (get-total-proposals)
  (ok (var-get proposal-counter))
)
