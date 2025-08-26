;; title: TelemedicinePaymentHub
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;
;; Telemedicine Payment Hub
;; Automated payment system for telehealth services with outcome-based pricing

;; Define the payment token (using STX for this implementation)
;; In production, this could be extended to support multiple tokens

;; Constants

(define-constant contract-owner (as-contract tx-sender))

(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-service-not-found (err u104))
(define-constant err-already-completed (err u105))

;; Data structures
(define-map service-payments
  { service-id: uint, patient: principal }
  {
    provider: principal,
    base-amount: uint,
    outcome-bonus: uint,
    is-completed: bool,
    outcome-achieved: bool,
    payment-released: bool
  }
)

(define-map provider-balances principal uint)
(define-data-var next-service-id uint u1)

;; Function 1: Create Service Payment Escrow
;; Patients can create an escrow payment for a telehealth service
(define-public (create-service-payment (provider principal) (base-amount uint) (outcome-bonus uint))
  (let 
    (
      (service-id (var-get next-service-id))
      (total-payment (+ base-amount outcome-bonus))
    )
    (begin
      ;; Validate inputs
      (asserts! (> base-amount u0) err-invalid-amount)
      (asserts! (>= outcome-bonus u0) err-invalid-amount)
      
      ;; Transfer total payment amount to contract escrow
      (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
      
      ;; Store service payment details
      (map-set service-payments
        { service-id: service-id, patient: tx-sender }
        {
        provider: provider,
          base-amount: base-amount,
          outcome-bonus: outcome-bonus,
          is-completed: false,
          outcome-achieved: false,
          payment-released: false
        }
      )
      
      ;; Increment service ID for next service
      (var-set next-service-id (+ service-id u1))
      
      ;; Print event for off-chain tracking
      (print {
        event: "service-payment-created",
        service-id: service-id,
        patient: tx-sender,
        provider: provider,
        base-amount: base-amount,
        outcome-bonus: outcome-bonus
      })
      
      (ok service-id)
    )
  )
)

;; Function 2: Complete Service and Release Payment
;; Providers can complete the service and release payment based on outcomes
(define-public (complete-service-payment (service-id uint) (patient principal) (outcome-achieved bool))
  (let 
    (
      (service-key { service-id: service-id, patient: patient })
      (service-data (unwrap! (map-get? service-payments service-key) err-service-not-found))
    )
    (begin
      ;; Validate caller is the assigned provider
      (asserts! (is-eq tx-sender (get provider service-data)) err-unauthorized)
      
      ;; Ensure service hasn't been completed yet
      (asserts! (not (get is-completed service-data)) err-already-completed)
      
      ;; Calculate payment amount based on outcome
      (let 
        (
          (payment-amount 
            (if outcome-achieved
              (+ (get base-amount service-data) (get outcome-bonus service-data))
              (get base-amount service-data)
            )
          )
        )
        (begin
          ;; Transfer payment to provider
          (try! (as-contract (stx-transfer? payment-amount tx-sender (get provider service-data))))
          
          ;; If there's remaining funds (when outcome not achieved), refund to patient
          (if (not outcome-achieved)
            (try! (as-contract (stx-transfer? (get outcome-bonus service-data) tx-sender patient)))
            true
          )
          
          ;; Update service status
          (map-set service-payments service-key
            (merge service-data {
              is-completed: true,
              outcome-achieved: outcome-achieved,
              payment-released: true
            })
          )
          
          ;; Update provider balance tracking
          (map-set provider-balances 
            (get provider service-data)
            (+ (default-to u0 (map-get? provider-balances (get provider service-data))) payment-amount)
          )
          
          ;; Print completion event
          (print {
            event: "service-completed",
            service-id: service-id,
            patient: patient,
            provider: (get provider service-data),
            outcome-achieved: outcome-achieved,
            payment-amount: payment-amount
          })
          
          (ok payment-amount)
        )
      )
    )
  )
)

;; Read-only functions for querying service and payment data

(define-read-only (get-service-payment (service-id uint) (patient principal))
  (map-get? service-payments { service-id: service-id, patient: patient })
)

(define-read-only (get-provider-balance (provider principal))
  (default-to u0 (map-get? provider-balances provider))
)

(define-read-only (get-next-service-id)
  (var-get next-service-id)
)
