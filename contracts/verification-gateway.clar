;; title: verification-gateway
;; version: 1.0.0
;; summary: Medicine authenticity verification interface
;; description: Enables pharmacies and consumers to verify drug authenticity and report counterfeits

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-not-authorized (err u401))
(define-constant err-verification-failed (err u402))
(define-constant err-invalid-batch (err u403))
(define-constant err-batch-not-found (err u404))
(define-constant err-already-reported (err u405))
(define-constant err-pharmacy-not-registered (err u406))
(define-constant err-invalid-report (err u407))

;; Verification result constants
(define-constant verify-authentic u1)
(define-constant verify-recalled u2)
(define-constant verify-expired u3)
(define-constant verify-counterfeit u4)
(define-constant verify-not-found u5)

;; Data Variables
(define-data-var verification-counter uint u0)
(define-data-var total-pharmacies uint u0)
(define-data-var total-counterfeit-reports uint u0)
(define-data-var total-verifications uint u0)

;; Data Maps

;; Registered pharmacies and verifiers
(define-map pharmacies
  { pharmacy: principal }
  {
    name: (string-ascii 100),
    license: (string-ascii 50),
    registered-at: uint,
    is-active: bool,
    total-verifications: uint
  }
)

;; Verification records
(define-map verifications
  { verification-id: uint }
  {
    batch-id: (string-ascii 64),
    verifier: principal,
    verified-at: uint,
    result: uint,
    location: (string-ascii 100)
  }
)

;; Batch verification history
(define-map batch-verification-history
  { batch-id: (string-ascii 64), timestamp: uint }
  {
    verifier: principal,
    result: uint,
    location: (string-ascii 100)
  }
)

;; Verifier history index
(define-map verifier-history
  { verifier: principal }
  { verification-ids: (list 100 uint), total-count: uint }
)

;; Counterfeit reports
(define-map counterfeit-reports
  { batch-id: (string-ascii 64), reporter: principal }
  {
    reported-at: uint,
    description: (string-ascii 200),
    location: (string-ascii 100),
    evidence: (string-ascii 100),
    status: (string-ascii 20)
  }
)

;; Batch scan counter
(define-map batch-scan-count
  { batch-id: (string-ascii 64) }
  { total-scans: uint, unique-scanners: uint }
)

;; Consumer verification tracking
(define-map consumer-verifications
  { consumer: principal, batch-id: (string-ascii 64) }
  {
    verified-at: uint,
    result: uint,
    feedback-provided: bool
  }
)

;; Pharmacy verification statistics
(define-map pharmacy-stats
  { pharmacy: principal }
  {
    authentic-count: uint,
    counterfeit-found: uint,
    last-verification: uint
  }
)

;; Public Functions

;; Register a pharmacy or verification entity
(define-public (register-pharmacy (name (string-ascii 100)) (license (string-ascii 50)))
  (let
    (
      (pharmacy tx-sender)
    )
    (asserts! (is-none (map-get? pharmacies { pharmacy: pharmacy }))
      (err u405)) ;; Already registered
    (asserts! (> (len name) u0) err-invalid-report)
    (asserts! (> (len license) u0) err-invalid-report)
    
    (map-set pharmacies
      { pharmacy: pharmacy }
      {
        name: name,
        license: license,
        registered-at: stacks-block-height,
        is-active: true,
        total-verifications: u0
      }
    )
    
    (map-set pharmacy-stats
      { pharmacy: pharmacy }
      { authentic-count: u0, counterfeit-found: u0, last-verification: u0 }
    )
    
    (var-set total-pharmacies (+ (var-get total-pharmacies) u1))
    (ok true)
  )
)

;; Verify medicine authenticity
(define-public (verify-batch (batch-id (string-ascii 64)) (location (string-ascii 100)))
  (let
    (
      (verifier tx-sender)
      (new-verification-id (+ (var-get verification-counter) u1))
      (verification-result (determine-verification-result batch-id))
    )
    ;; Record verification
    (map-set verifications
      { verification-id: new-verification-id }
      {
        batch-id: batch-id,
        verifier: verifier,
        verified-at: stacks-block-height,
        result: verification-result,
        location: location
      }
    )
    
    ;; Update batch verification history
    (map-set batch-verification-history
      { batch-id: batch-id, timestamp: stacks-block-height }
      {
        verifier: verifier,
        result: verification-result,
        location: location
      }
    )
    
    ;; Update verifier history
    (match (map-get? verifier-history { verifier: verifier })
      existing-history
        (map-set verifier-history
          { verifier: verifier }
          {
            verification-ids: (unwrap-panic (as-max-len? (append (get verification-ids existing-history) new-verification-id) u100)),
            total-count: (+ (get total-count existing-history) u1)
          }
        )
      ;; First verification for verifier
      (map-set verifier-history
        { verifier: verifier }
        { verification-ids: (list new-verification-id), total-count: u1 }
      )
    )
    
    ;; Update scan counter
    (match (map-get? batch-scan-count { batch-id: batch-id })
      existing-count
        (map-set batch-scan-count
          { batch-id: batch-id }
          {
            total-scans: (+ (get total-scans existing-count) u1),
            unique-scanners: (get unique-scanners existing-count)
          }
        )
      ;; First scan
      (map-set batch-scan-count
        { batch-id: batch-id }
        { total-scans: u1, unique-scanners: u1 }
      )
    )
    
    ;; Update pharmacy stats if verifier is registered pharmacy
    (match (map-get? pharmacies { pharmacy: verifier })
      pharmacy-info
        (begin
          (map-set pharmacies
            { pharmacy: verifier }
            (merge pharmacy-info { total-verifications: (+ (get total-verifications pharmacy-info) u1) })
          )
          (match (map-get? pharmacy-stats { pharmacy: verifier })
            stats
              (if (is-eq verification-result verify-authentic)
                (map-set pharmacy-stats
                  { pharmacy: verifier }
                  (merge stats {
                    authentic-count: (+ (get authentic-count stats) u1),
                    last-verification: stacks-block-height
                  })
                )
                (map-set pharmacy-stats
                  { pharmacy: verifier }
                  (merge stats {
                    counterfeit-found: (+ (get counterfeit-found stats) u1),
                    last-verification: stacks-block-height
                  })
                )
              )
            true
          )
        )
      true
    )
    
    (var-set verification-counter new-verification-id)
    (var-set total-verifications (+ (var-get total-verifications) u1))
    (ok verification-result)
  )
)

;; Report suspected counterfeit
(define-public (report-counterfeit 
  (batch-id (string-ascii 64))
  (description (string-ascii 200))
  (location (string-ascii 100))
  (evidence (string-ascii 100))
)
  (let
    (
      (reporter tx-sender)
    )
    (asserts! (is-none (map-get? counterfeit-reports { batch-id: batch-id, reporter: reporter }))
      err-already-reported)
    (asserts! (> (len description) u0) err-invalid-report)
    
    (map-set counterfeit-reports
      { batch-id: batch-id, reporter: reporter }
      {
        reported-at: stacks-block-height,
        description: description,
        location: location,
        evidence: evidence,
        status: "pending"
      }
    )
    
    (var-set total-counterfeit-reports (+ (var-get total-counterfeit-reports) u1))
    (ok true)
  )
)

;; Consumer verification with feedback
(define-public (consumer-verify (batch-id (string-ascii 64)))
  (let
    (
      (consumer tx-sender)
      (verification-result (determine-verification-result batch-id))
    )
    (map-set consumer-verifications
      { consumer: consumer, batch-id: batch-id }
      {
        verified-at: stacks-block-height,
        result: verification-result,
        feedback-provided: false
      }
    )
    
    (var-set total-verifications (+ (var-get total-verifications) u1))
    (ok verification-result)
  )
)

;; Read-only Functions

;; Determine verification result (simplified - in real implementation would check drug-registry)
(define-private (determine-verification-result (batch-id (string-ascii 64)))
  ;; Simplified: Returns verify-authentic 
  ;; In real implementation, this would check the drug-registry contract
  verify-authentic
)

;; Get verification record
(define-read-only (get-verification (verification-id uint))
  (ok (map-get? verifications { verification-id: verification-id }))
)

;; Get batch verification history
(define-read-only (get-batch-verification-history (batch-id (string-ascii 64)) (timestamp uint))
  (ok (map-get? batch-verification-history { batch-id: batch-id, timestamp: timestamp }))
)

;; Get verifier history
(define-read-only (get-verifier-history (verifier principal))
  (ok (map-get? verifier-history { verifier: verifier }))
)

;; Get pharmacy information
(define-read-only (get-pharmacy (pharmacy principal))
  (ok (map-get? pharmacies { pharmacy: pharmacy }))
)

;; Get pharmacy stats
(define-read-only (get-pharmacy-stats (pharmacy principal))
  (ok (map-get? pharmacy-stats { pharmacy: pharmacy }))
)

;; Get counterfeit report
(define-read-only (get-counterfeit-report (batch-id (string-ascii 64)) (reporter principal))
  (ok (map-get? counterfeit-reports { batch-id: batch-id, reporter: reporter }))
)

;; Get batch scan count
(define-read-only (get-batch-scan-count (batch-id (string-ascii 64)))
  (ok (map-get? batch-scan-count { batch-id: batch-id }))
)

;; Get consumer verification
(define-read-only (get-consumer-verification (consumer principal) (batch-id (string-ascii 64)))
  (ok (map-get? consumer-verifications { consumer: consumer, batch-id: batch-id }))
)

;; Get total verifications
(define-read-only (get-total-verifications)
  (ok (var-get total-verifications))
)

;; Get total pharmacies
(define-read-only (get-total-pharmacies)
  (ok (var-get total-pharmacies))
)

;; Get total counterfeit reports
(define-read-only (get-total-counterfeit-reports)
  (ok (var-get total-counterfeit-reports))
)

;; Check if pharmacy is registered
(define-read-only (is-pharmacy-registered (pharmacy principal))
  (match (map-get? pharmacies { pharmacy: pharmacy })
    pharmacy-info (ok (get is-active pharmacy-info))
    (ok false)
  )
)

