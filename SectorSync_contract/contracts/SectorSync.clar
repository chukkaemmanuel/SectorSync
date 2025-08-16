;; title: SectorSync - Synthetic Assets Platform
;; version: 1.0.0
;; summary: Provides sector-based synthetic exposure to traditional assets (tech, healthcare, energy)
;; description: A smart contract that enables users to mint, trade, and redeem synthetic tokens
;;              representing exposure to different market sectors

;; traits
;;

;; token definitions
(define-fungible-token sector-tech)
(define-fungible-token sector-healthcare)
(define-fungible-token sector-energy)

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_INVALID_SECTOR (err u103))
(define-constant ERR_PRICE_FEED_ERROR (err u104))
(define-constant ERR_COLLATERAL_INSUFFICIENT (err u105))

;; Supported sectors
(define-constant SECTOR_TECH u1)
(define-constant SECTOR_HEALTHCARE u2)
(define-constant SECTOR_ENERGY u3)

;; Collateral ratio (150% = 1.5 * 10^6 for precision)
(define-constant COLLATERAL_RATIO u1500000)
(define-constant PRECISION u1000000)

;; data vars
(define-data-var contract-enabled bool true)
(define-data-var total-collateral uint u0)

;; Price feeds (simulated - in production would use oracle)
(define-data-var tech-price uint u100000000) ;; $100 with 6 decimal precision
(define-data-var healthcare-price uint u85000000) ;; $85 with 6 decimal precision
(define-data-var energy-price uint u75000000) ;; $75 with 6 decimal precision

;; data maps
(define-map user-collateral principal uint)
(define-map sector-collateral uint uint)
(define-map authorized-operators principal bool)

;; public functions

;; Initialize contract (can only be called once by owner)
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set authorized-operators CONTRACT_OWNER true)
    (ok true)
  )
)

;; Add collateral to mint synthetic tokens
(define-public (add-collateral (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    
    ;; Transfer STX as collateral
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update user collateral
    (map-set user-collateral tx-sender 
      (+ (default-to u0 (map-get? user-collateral tx-sender)) amount))
    
    ;; Update total collateral
    (var-set total-collateral (+ (var-get total-collateral) amount))
    
    (ok amount)
  )
)

;; Mint synthetic tokens for a specific sector
(define-public (mint-synthetic (sector uint) (amount uint))
  (let (
    (user-collateral-balance (default-to u0 (map-get? user-collateral tx-sender)))
    (sector-price (get-sector-price sector))
    (required-collateral (/ (* amount sector-price COLLATERAL_RATIO) (* PRECISION PRECISION)))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    (asserts! (>= user-collateral-balance required-collateral) ERR_COLLATERAL_INSUFFICIENT)
    
    ;; Mint tokens based on sector
    (try! (if (is-eq sector SECTOR_TECH)
      (ft-mint? sector-tech amount tx-sender)
      (if (is-eq sector SECTOR_HEALTHCARE)
        (ft-mint? sector-healthcare amount tx-sender)
        (if (is-eq sector SECTOR_ENERGY)
          (ft-mint? sector-energy amount tx-sender)
          ERR_INVALID_SECTOR
        )
      )
    ))
    
    ;; Update sector collateral tracking
    (map-set sector-collateral sector 
      (+ (default-to u0 (map-get? sector-collateral sector)) required-collateral))
    
    (ok amount)
  )
)

;; Burn synthetic tokens and release collateral
(define-public (burn-synthetic (sector uint) (amount uint))
  (let (
    (sector-price (get-sector-price sector))
    (collateral-to-release (/ (* amount sector-price COLLATERAL_RATIO) (* PRECISION PRECISION)))
    (user-collateral-balance (default-to u0 (map-get? user-collateral tx-sender)))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    
    ;; Burn tokens based on sector
    (try! (if (is-eq sector SECTOR_TECH)
      (ft-burn? sector-tech amount tx-sender)
      (if (is-eq sector SECTOR_HEALTHCARE)
        (ft-burn? sector-healthcare amount tx-sender)
        (if (is-eq sector SECTOR_ENERGY)
          (ft-burn? sector-energy amount tx-sender)
          ERR_INVALID_SECTOR
        )
      )
    ))
    
    ;; Update collateral tracking
    (map-set user-collateral tx-sender (- user-collateral-balance collateral-to-release))
    (map-set sector-collateral sector 
      (- (default-to u0 (map-get? sector-collateral sector)) collateral-to-release))
    (var-set total-collateral (- (var-get total-collateral) collateral-to-release))
    
    ;; Transfer collateral back to user
    (try! (as-contract (stx-transfer? collateral-to-release tx-sender tx-sender)))
    
    (ok amount)
  )
)

;; Transfer synthetic tokens
(define-public (transfer-synthetic (sector uint) (amount uint) (recipient principal))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    
    (if (is-eq sector SECTOR_TECH)
      (ft-transfer? sector-tech amount tx-sender recipient)
      (if (is-eq sector SECTOR_HEALTHCARE)
        (ft-transfer? sector-healthcare amount tx-sender recipient)
        (if (is-eq sector SECTOR_ENERGY)
          (ft-transfer? sector-energy amount tx-sender recipient)
          ERR_INVALID_SECTOR
        )
      )
    )
  )
)

;; Admin function to update price feeds
(define-public (update-price (sector uint) (new-price uint))
  (begin
    (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR_NOT_AUTHORIZED)
    (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
    
    (if (is-eq sector SECTOR_TECH)
      (begin (var-set tech-price new-price) (ok new-price))
      (if (is-eq sector SECTOR_HEALTHCARE)
        (begin (var-set healthcare-price new-price) (ok new-price))
        (if (is-eq sector SECTOR_ENERGY)
          (begin (var-set energy-price new-price) (ok new-price))
          ERR_INVALID_SECTOR
        )
      )
    )
  )
)

;; Admin function to toggle contract
(define-public (toggle-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-enabled (not (var-get contract-enabled)))
    (ok (var-get contract-enabled))
  )
)

;; Admin function to add authorized operators
(define-public (add-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set authorized-operators operator true)
    (ok true)
  )
)

;; read only functions

;; Get sector price
(define-read-only (get-sector-price (sector uint))
  (if (is-eq sector SECTOR_TECH)
    (var-get tech-price)
    (if (is-eq sector SECTOR_HEALTHCARE)
      (var-get healthcare-price)
      (if (is-eq sector SECTOR_ENERGY)
        (var-get energy-price)
        u0
      )
    )
  )
)

;; Get user's collateral balance
(define-read-only (get-user-collateral (user principal))
  (default-to u0 (map-get? user-collateral user))
)

;; Get user's synthetic token balance
(define-read-only (get-synthetic-balance (sector uint) (user principal))
  (if (is-eq sector SECTOR_TECH)
    (ft-get-balance sector-tech user)
    (if (is-eq sector SECTOR_HEALTHCARE)
      (ft-get-balance sector-healthcare user)
      (if (is-eq sector SECTOR_ENERGY)
        (ft-get-balance sector-energy user)
        u0
      )
    )
  )
)

;; Get total supply for a sector
(define-read-only (get-total-supply (sector uint))
  (if (is-eq sector SECTOR_TECH)
    (ft-get-supply sector-tech)
    (if (is-eq sector SECTOR_HEALTHCARE)
      (ft-get-supply sector-healthcare)
      (if (is-eq sector SECTOR_ENERGY)
        (ft-get-supply sector-energy)
        u0
      )
    )
  )
)

;; Get sector collateral
(define-read-only (get-sector-collateral (sector uint))
  (default-to u0 (map-get? sector-collateral sector))
)

;; Get total collateral
(define-read-only (get-total-collateral)
  (var-get total-collateral)
)

;; Check if contract is enabled
(define-read-only (is-contract-enabled)
  (var-get contract-enabled)
)

;; Calculate required collateral for minting
(define-read-only (calculate-collateral-required (sector uint) (amount uint))
  (let (
    (sector-price (get-sector-price sector))
  )
    (/ (* amount sector-price COLLATERAL_RATIO) (* PRECISION PRECISION))
  )
)

;; Get contract info
(define-read-only (get-contract-info)
  {
    owner: CONTRACT_OWNER,
    enabled: (var-get contract-enabled),
    total-collateral: (var-get total-collateral),
    tech-price: (var-get tech-price),
    healthcare-price: (var-get healthcare-price),
    energy-price: (var-get energy-price)
  }
)

;; private functions

;; Validate sector ID
(define-private (is-valid-sector (sector uint))
  (or (is-eq sector SECTOR_TECH)
      (or (is-eq sector SECTOR_HEALTHCARE) 
          (is-eq sector SECTOR_ENERGY))))