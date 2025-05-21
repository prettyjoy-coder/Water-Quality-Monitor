;; Water Quality Monitoring Smart Contract
;; This contract allows monitoring and verification of water quality data 
;; collected from various sensors and testing facilities

(define-data-var contract-owner principal tx-sender)
(define-data-var admin-list (list 10 principal) (list))

;; Data structure for water quality readings
(define-map water-quality-readings 
  {
    location-id: uint,
    timestamp: uint
  }
  {
    ph-level: uint,              ;; pH * 100 (e.g., 700 = pH 7.0)
    dissolved-oxygen: uint,      ;; DO in mg/L * 100
    turbidity: uint,             ;; NTU * 100
    temperature: uint,           ;; Celsius * 100
    conductivity: uint,          ;; uS/cm
    total-dissolved-solids: uint,;; TDS in mg/L
    verified: bool,
    verifier: (optional principal)
  }
)

;; Map to track authorized data providers
(define-map authorized-providers principal bool)

;; Map to track testing facilities by ID
(define-map testing-facilities 
  uint 
  {
    facility-name: (string-ascii 50),
    location: (string-ascii 100),
    active: bool
  }
)

;; Location registry
(define-map locations
  uint
  {
    name: (string-ascii 50),
    latitude: int,    ;; Latitude * 1,000,000
    longitude: int,   ;; Longitude * 1,000,000
    location-type: (string-ascii 20),
    active: bool
  }
)

;; Keep track of the number of locations and facilities
(define-data-var next-location-id uint u1)
(define-data-var next-facility-id uint u1)

;; Events
(define-trait water-quality-event 
  (
    (emit-reading (uint uint uint uint uint uint uint uint bool) (response bool uint))
  )
)

;; Constants for water quality standards
(define-constant ERR-UNAUTHORIZED u1)
(define-constant ERR-INVALID-DATA u2)
(define-constant ERR-NOT-FOUND u3)
(define-constant ERR-ALREADY-VERIFIED u4)
(define-constant ERR-INVALID-RANGE u5)
(define-constant SAFE-PH-MIN u650)     ;; 6.5
(define-constant SAFE-PH-MAX u850)     ;; 8.5
(define-constant MIN-DISSOLVED-OXYGEN u400) ;; 4 mg/L

;; Initialize contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-UNAUTHORIZED))
    (ok true)
  )
)

;; Add an admin
(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    (let ((current-admins (var-get admin-list)))
      (asserts! (< (len current-admins) u10) (err ERR-INVALID-RANGE))
      ;; Create a new list instead of using append to avoid type mismatch
      (let ((new-admin-list 
              (unwrap! (as-max-len? (concat current-admins (list new-admin)) u10) 
                      (err ERR-INVALID-RANGE))))
        (var-set admin-list new-admin-list)
        (ok true)
      )
    )
  )
)

;; Check if principal is an admin
(define-read-only (is-admin (address principal))
  (is-some (index-of (var-get admin-list) address))
)

;; Add authorized provider
(define-public (add-provider (provider principal))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    (map-set authorized-providers provider true)
    (ok true)
  )
)

;; Remove authorized provider
(define-public (remove-provider (provider principal))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    (map-set authorized-providers provider false)
    (ok true)
  )
)

;; Check if provider is authorized
(define-read-only (is-authorized-provider (provider principal))
  (default-to false (map-get? authorized-providers provider))
)

;; Add a new testing facility
(define-public (add-testing-facility 
                (facility-name (string-ascii 50)) 
                (location (string-ascii 100)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    (let ((facility-id (var-get next-facility-id)))
      (map-set testing-facilities 
               facility-id 
               {
                 facility-name: facility-name,
                 location: location,
                 active: true
               })
      (var-set next-facility-id (+ facility-id u1))
      (ok facility-id)
    )
  )
)

;; Add a new monitoring location
(define-public (add-location 
                (name (string-ascii 50)) 
                (latitude int) 
                (longitude int) 
                (location-type (string-ascii 20)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    (let ((location-id (var-get next-location-id)))
      (map-set locations 
               location-id 
               {
                 name: name,
                 latitude: latitude,
                 longitude: longitude,
                 location-type: location-type,
                 active: true
               })
      (var-set next-location-id (+ location-id u1))
      (ok location-id)
    )
  )
)

;; Submit water quality reading
(define-public (submit-reading
                (location-id uint)
                (timestamp uint)
                (ph-level uint)
                (dissolved-oxygen uint)
                (turbidity uint)
                (temperature uint)
                (conductivity uint)
                (total-dissolved-solids uint))
  (begin
    (asserts! (is-authorized-provider tx-sender) (err ERR-UNAUTHORIZED))
    (asserts! (is-some (map-get? locations location-id)) (err ERR-NOT-FOUND))
    (asserts! (and (>= ph-level u0) (<= ph-level u1400)) (err ERR-INVALID-DATA))
    (asserts! (>= dissolved-oxygen u0) (err ERR-INVALID-DATA))
    
    (map-set water-quality-readings
             {
               location-id: location-id,
               timestamp: timestamp
             }
             {
               ph-level: ph-level,
               dissolved-oxygen: dissolved-oxygen,
               turbidity: turbidity,
               temperature: temperature,
               conductivity: conductivity,
               total-dissolved-solids: total-dissolved-solids,
               verified: false,
               verifier: none
             })
    (ok true)
  )
)

;; Verify a water quality reading
(define-public (verify-reading
                (location-id uint)
                (timestamp uint))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    (let ((reading (map-get? water-quality-readings {location-id: location-id, timestamp: timestamp})))
      (asserts! (is-some reading) (err ERR-NOT-FOUND))
      (asserts! (not (get verified (unwrap! reading (err ERR-NOT-FOUND)))) (err ERR-ALREADY-VERIFIED))
      
      (map-set water-quality-readings
               {
                 location-id: location-id,
                 timestamp: timestamp
               }
               (merge (unwrap! reading (err ERR-NOT-FOUND))
                      {
                        verified: true,
                        verifier: (some tx-sender)
                      }))
      (ok true)
    )
  )
)

;; Get water quality reading
(define-read-only (get-reading
                    (location-id uint)
                    (timestamp uint))
  (map-get? water-quality-readings {location-id: location-id, timestamp: timestamp})
)

;; Check if water quality meets safety standards
(define-read-only (is-water-safe
                    (location-id uint)
                    (timestamp uint))
  (let ((reading (map-get? water-quality-readings {location-id: location-id, timestamp: timestamp})))
    (if (is-some reading)
      (let ((unwrapped-reading (unwrap-panic reading)))
        (and (>= (get ph-level unwrapped-reading) SAFE-PH-MIN)
             (<= (get ph-level unwrapped-reading) SAFE-PH-MAX)
             (>= (get dissolved-oxygen unwrapped-reading) MIN-DISSOLVED-OXYGEN)
             (get verified unwrapped-reading)))
      false)
  )
)

;; Get location information
(define-read-only (get-location (location-id uint))
  (map-get? locations location-id)
)

;; Get facility information
(define-read-only (get-facility (facility-id uint))
  (map-get? testing-facilities facility-id)
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-UNAUTHORIZED))
    (var-set contract-owner new-owner)
    (ok true)
  )
)