;; title: drug-registry
;; version: 1.0.0
;; summary: Medicine batch registration and tracking system
;; description: Maintains authoritative records of pharmaceutical batches with manufacturer verification

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-authorized (err u301))
(define-constant err-batch-not-found (err u302))
(define-constant err-invalid-batch (err u303))
(define-constant err-batch-exists (err u304))
(define-constant err-not-manufacturer (err u305))
(define-constant err-invalid-expiry (err u306))
(define-constant err-batch-recalled (err u307))
(define-constant err-empty-data (err u308))

;; Batch status constants
(define-constant status-active u1)
(define-constant status-recalled u2)
(define-constant status-expired u3)
(define-constant status-depleted u4)

;; Data Variables
(define-data-var batch-counter uint u0)
(define-data-var total-manufacturers uint u0)
(define-data-var total-recalls uint u0)

;; Data Maps

;; Manufacturer registry
(define-map manufacturers
  { manufacturer: principal }
  {
    company-name: (string-ascii 100),
    registered-at: uint,
    is-verified: bool,
    license-number: (string-ascii 50),
    total-batches: uint
  }
)

;; Main batch records
(define-map drug-batches
  { batch-id: (string-ascii 64) }
  {
    batch-number: uint,
    manufacturer: principal,
    drug-name: (string-ascii 100),
    dosage: (string-ascii 50),
    formulation: (string-ascii 50),
    quantity: uint,
    manufactured-date: uint,
    expiry-date: uint,
    status: uint,
    registered-at: uint
  }
)

;; Batch metadata and additional information
(define-map batch-metadata
  { batch-id: (string-ascii 64) }
  {
    manufacturing-location: (string-ascii 100),
    lot-number: (string-ascii 50),
    ndc-code: (string-ascii 20),
    ingredients: (string-ascii 200),
    storage-conditions: (string-ascii 100)
  }
)

;; Manufacturer batch index
(define-map manufacturer-batches
  { manufacturer: principal }
  { batch-ids: (list 200 (string-ascii 64)), batch-count: uint }
)

;; Batch distribution tracking
(define-map batch-distribution
  { batch-id: (string-ascii 64), distributor: principal }
  {
    distributed-at: uint,
    quantity: uint,
    destination: (string-ascii 100)
  }
)

;; Recall information
(define-map recall-records
  { batch-id: (string-ascii 64) }
  {
    recalled-at: uint,
    reason: (string-ascii 200),
    recalled-by: principal,
    severity: uint
  }
)

;; Batch history log
(define-map batch-log
  { batch-id: (string-ascii 64), timestamp: uint }
  {
    action: (string-ascii 20),
    actor: principal,
    details: (string-ascii 100)
  }
)

;; Quality control records
(define-map quality-control
  { batch-id: (string-ascii 64) }
  {
    test-date: uint,
    test-results: (string-ascii 100),
    approved: bool,
    inspector: principal
  }
)

;; Public Functions

;; Register a new manufacturer
(define-public (register-manufacturer (company-name (string-ascii 100)) (license-number (string-ascii 50)))
  (let
    (
      (manufacturer tx-sender)
    )
    (asserts! (is-none (map-get? manufacturers { manufacturer: manufacturer }))
      (err u304)) ;; Already registered
    (asserts! (> (len company-name) u0) err-empty-data)
    (asserts! (> (len license-number) u0) err-empty-data)
    
    (map-set manufacturers
      { manufacturer: manufacturer }
      {
        company-name: company-name,
        registered-at: stacks-block-height,
        is-verified: true,
        license-number: license-number,
        total-batches: u0
      }
    )
    
    (var-set total-manufacturers (+ (var-get total-manufacturers) u1))
    (ok true)
  )
)

;; Register a new drug batch
(define-public (register-batch 
  (batch-id (string-ascii 64))
  (drug-name (string-ascii 100))
  (dosage (string-ascii 50))
  (formulation (string-ascii 50))
  (quantity uint)
  (manufactured-date uint)
  (expiry-date uint)
  (manufacturing-location (string-ascii 100))
  (lot-number (string-ascii 50))
  (ndc-code (string-ascii 20))
  (ingredients (string-ascii 200))
  (storage-conditions (string-ascii 100))
)
  (let
    (
      (manufacturer tx-sender)
      (mfg-info (unwrap! (map-get? manufacturers { manufacturer: manufacturer }) err-not-manufacturer))
      (new-batch-number (+ (var-get batch-counter) u1))
    )
    ;; Validation
    (asserts! (get is-verified mfg-info) err-not-authorized)
    (asserts! (is-none (map-get? drug-batches { batch-id: batch-id })) err-batch-exists)
    (asserts! (> expiry-date manufactured-date) err-invalid-expiry)
    (asserts! (> expiry-date stacks-block-height) err-invalid-expiry)
    (asserts! (> (len drug-name) u0) err-empty-data)
    (asserts! (> quantity u0) err-invalid-batch)
    
    ;; Register batch
    (map-set drug-batches
      { batch-id: batch-id }
      {
        batch-number: new-batch-number,
        manufacturer: manufacturer,
        drug-name: drug-name,
        dosage: dosage,
        formulation: formulation,
        quantity: quantity,
        manufactured-date: manufactured-date,
        expiry-date: expiry-date,
        status: status-active,
        registered-at: stacks-block-height
      }
    )
    
    ;; Store metadata
    (map-set batch-metadata
      { batch-id: batch-id }
      {
        manufacturing-location: manufacturing-location,
        lot-number: lot-number,
        ndc-code: ndc-code,
        ingredients: ingredients,
        storage-conditions: storage-conditions
      }
    )
    
    ;; Update manufacturer batch index
    (match (map-get? manufacturer-batches { manufacturer: manufacturer })
      existing-batches
        (map-set manufacturer-batches
          { manufacturer: manufacturer }
          {
            batch-ids: (unwrap-panic (as-max-len? (append (get batch-ids existing-batches) batch-id) u200)),
            batch-count: (+ (get batch-count existing-batches) u1)
          }
        )
      ;; First batch for manufacturer
      (map-set manufacturer-batches
        { manufacturer: manufacturer }
        { batch-ids: (list batch-id), batch-count: u1 }
      )
    )
    
    ;; Update manufacturer total batches
    (map-set manufacturers
      { manufacturer: manufacturer }
      (merge mfg-info { total-batches: (+ (get total-batches mfg-info) u1) })
    )
    
    ;; Log the registration
    (map-set batch-log
      { batch-id: batch-id, timestamp: stacks-block-height }
      { action: "registered", actor: manufacturer, details: drug-name }
    )
    
    (var-set batch-counter new-batch-number)
    (ok batch-id)
  )
)

;; Record quality control test
(define-public (record-quality-test (batch-id (string-ascii 64)) (test-results (string-ascii 100)) (approved bool))
  (let
    (
      (batch (unwrap! (map-get? drug-batches { batch-id: batch-id }) err-batch-not-found))
      (inspector tx-sender)
    )
    (asserts! (is-eq (get manufacturer batch) inspector) err-not-authorized)
    (asserts! (is-eq (get status batch) status-active) err-batch-recalled)
    
    (map-set quality-control
      { batch-id: batch-id }
      {
        test-date: stacks-block-height,
        test-results: test-results,
        approved: approved,
        inspector: inspector
      }
    )
    
    (map-set batch-log
      { batch-id: batch-id, timestamp: stacks-block-height }
      { action: "qc-tested", actor: inspector, details: test-results }
    )
    
    (ok true)
  )
)

;; Record batch distribution
(define-public (record-distribution (batch-id (string-ascii 64)) (quantity uint) (destination (string-ascii 100)))
  (let
    (
      (batch (unwrap! (map-get? drug-batches { batch-id: batch-id }) err-batch-not-found))
      (distributor tx-sender)
    )
    (asserts! (is-eq (get status batch) status-active) err-batch-recalled)
    (asserts! (> quantity u0) err-invalid-batch)
    (asserts! (<= quantity (get quantity batch)) err-invalid-batch)
    
    (map-set batch-distribution
      { batch-id: batch-id, distributor: distributor }
      {
        distributed-at: stacks-block-height,
        quantity: quantity,
        destination: destination
      }
    )
    
    (map-set batch-log
      { batch-id: batch-id, timestamp: stacks-block-height }
      { action: "distributed", actor: distributor, details: destination }
    )
    
    (ok true)
  )
)

;; Recall a batch
(define-public (recall-batch (batch-id (string-ascii 64)) (reason (string-ascii 200)) (severity uint))
  (let
    (
      (batch (unwrap! (map-get? drug-batches { batch-id: batch-id }) err-batch-not-found))
    )
    (asserts! (is-eq tx-sender (get manufacturer batch)) err-not-authorized)
    (asserts! (is-eq (get status batch) status-active) err-batch-recalled)
    
    ;; Update batch status
    (map-set drug-batches
      { batch-id: batch-id }
      (merge batch { status: status-recalled })
    )
    
    ;; Record recall details
    (map-set recall-records
      { batch-id: batch-id }
      {
        recalled-at: stacks-block-height,
        reason: reason,
        recalled-by: tx-sender,
        severity: severity
      }
    )
    
    (map-set batch-log
      { batch-id: batch-id, timestamp: stacks-block-height }
      { action: "recalled", actor: tx-sender, details: "batch recalled" }
    )
    
    (var-set total-recalls (+ (var-get total-recalls) u1))
    (ok true)
  )
)

;; Mark batch as expired
(define-public (mark-expired (batch-id (string-ascii 64)))
  (let
    (
      (batch (unwrap! (map-get? drug-batches { batch-id: batch-id }) err-batch-not-found))
    )
    (asserts! (>= stacks-block-height (get expiry-date batch)) err-invalid-expiry)
    
    (map-set drug-batches
      { batch-id: batch-id }
      (merge batch { status: status-expired })
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get batch information
(define-read-only (get-batch (batch-id (string-ascii 64)))
  (ok (map-get? drug-batches { batch-id: batch-id }))
)

;; Get batch metadata
(define-read-only (get-batch-metadata (batch-id (string-ascii 64)))
  (ok (map-get? batch-metadata { batch-id: batch-id }))
)

;; Get manufacturer information
(define-read-only (get-manufacturer (manufacturer principal))
  (ok (map-get? manufacturers { manufacturer: manufacturer }))
)

;; Get manufacturer batches
(define-read-only (get-manufacturer-batches (manufacturer principal))
  (ok (map-get? manufacturer-batches { manufacturer: manufacturer }))
)

;; Get quality control record
(define-read-only (get-quality-control (batch-id (string-ascii 64)))
  (ok (map-get? quality-control { batch-id: batch-id }))
)

;; Get distribution record
(define-read-only (get-distribution (batch-id (string-ascii 64)) (distributor principal))
  (ok (map-get? batch-distribution { batch-id: batch-id, distributor: distributor }))
)

;; Get recall information
(define-read-only (get-recall-info (batch-id (string-ascii 64)))
  (ok (map-get? recall-records { batch-id: batch-id }))
)

;; Get batch log entry
(define-read-only (get-batch-log (batch-id (string-ascii 64)) (timestamp uint))
  (ok (map-get? batch-log { batch-id: batch-id, timestamp: timestamp }))
)

;; Check if batch is valid (active and not expired)
(define-read-only (is-batch-valid (batch-id (string-ascii 64)))
  (match (map-get? drug-batches { batch-id: batch-id })
    batch
      (ok (and 
        (is-eq (get status batch) status-active)
        (< stacks-block-height (get expiry-date batch))
      ))
    (ok false)
  )
)

;; Get total batches registered
(define-read-only (get-total-batches)
  (ok (var-get batch-counter))
)

;; Get total manufacturers
(define-read-only (get-total-manufacturers)
  (ok (var-get total-manufacturers))
)

;; Get total recalls
(define-read-only (get-total-recalls)
  (ok (var-get total-recalls))
)

;; Check if caller is manufacturer of batch
(define-read-only (is-batch-manufacturer (batch-id (string-ascii 64)) (caller principal))
  (match (map-get? drug-batches { batch-id: batch-id })
    batch (ok (is-eq caller (get manufacturer batch)))
    (ok false)
  )
)

