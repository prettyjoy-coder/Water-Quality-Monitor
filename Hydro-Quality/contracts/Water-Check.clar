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
(define-constant ERR-INVALID-INPUT u6)
(define-constant SAFE-PH-MIN u650)     ;; 6.5
(define-constant SAFE-PH-MAX u850)     ;; 8.5
(define-constant MIN-DISSOLVED-OXYGEN u400) ;; 4 mg/L

;; Constants for input validation
(define-constant MAX-LATITUDE 90000000)  ;; 90.000000
(define-constant MIN-LATITUDE -90000000) ;; -90.000000
(define-constant MAX-LONGITUDE 180000000) ;; 180.000000
(define-constant MIN-LONGITUDE -180000000) ;; -180.000000

;; Maximum timestamp value (2^48 - 1)
(define-constant MAX-TIMESTAMP u281474976710655)

;; Maximum uint value for uint inputs
(define-constant MAX-UINT-VALUE u340282366920938463463374607431768211455) 

;; Initialize contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-UNAUTHORIZED))
    (ok true)
  )
)

;; Validation functions
(define-private (is-valid-string (str (string-ascii 100)))
  (> (len str) u0)
)

(define-private (is-valid-location-type (type (string-ascii 20)))
  (or 
    (is-eq type "river")
    (is-eq type "lake")
    (is-eq type "ocean")
    (is-eq type "reservoir")
    (is-eq type "groundwater")
    (is-eq type "stream")
    true ;; Allow other types for flexibility
  )
)

(define-private (is-valid-coordinates (lat int) (long int))
  (and 
    (>= lat MIN-LATITUDE)
    (<= lat MAX-LATITUDE)
    (>= long MIN-LONGITUDE)
    (<= long MAX-LONGITUDE)
  )
)

;; Validate location ID
(define-private (is-valid-location-id (id uint))
  (and 
    (> id u0)
    (< id (var-get next-location-id))
    (is-some (map-get? locations id))
  )
)

;; Validate timestamp
(define-private (is-valid-timestamp (timestamp uint))
  (and 
    (> timestamp u0)
    (<= timestamp MAX-TIMESTAMP)
  )
)

;; Add an admin
(define-public (add-admin (new-admin principal))
  (begin
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    ;; Check if admin already exists
    (asserts! (is-none (index-of (var-get admin-list) new-admin)) (err ERR-INVALID-INPUT))
    
    (let ((current-admins (var-get admin-list)))
      (asserts! (< (len current-admins) u10) (err ERR-INVALID-RANGE))
      ;; Create a new list with validated input
      (let ((validated-admin new-admin)
            (new-admin-list 
              (unwrap! (as-max-len? (concat current-admins (list validated-admin)) u10) 
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
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    ;; Ensure provider is not already authorized
    (asserts! (not (default-to false (map-get? authorized-providers provider))) 
              (err ERR-INVALID-INPUT))
    
    ;; Ensure provider is not the zero principal (basic validation)
    (asserts! (not (is-eq provider tx-sender)) (err ERR-INVALID-INPUT))
    
    ;; Set provider with validated input
    (map-set authorized-providers provider true)
    (ok true)
  )
)

;; Remove authorized provider
(define-public (remove-provider (provider principal))
  (begin
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    ;; Ensure provider is currently authorized
    (asserts! (default-to false (map-get? authorized-providers provider)) 
              (err ERR-INVALID-INPUT))
    
    ;; Remove provider with validated input
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
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    ;; Validate inputs
    (asserts! (is-valid-string facility-name) (err ERR-INVALID-INPUT))
    (asserts! (is-valid-string location) (err ERR-INVALID-INPUT))
    
    (let ((facility-id (var-get next-facility-id))
          (validated-name facility-name)
          (validated-location location))
      (map-set testing-facilities 
               facility-id 
               {
                 facility-name: validated-name,
                 location: validated-location,
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
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    ;; Validate inputs
    (asserts! (is-valid-string name) (err ERR-INVALID-INPUT))
    (asserts! (is-valid-coordinates latitude longitude) (err ERR-INVALID-RANGE))
    (asserts! (is-valid-location-type location-type) (err ERR-INVALID-INPUT))
    
    (let ((location-id (var-get next-location-id))
          (validated-name name)
          (validated-latitude latitude)
          (validated-longitude longitude)
          (validated-location-type location-type))
      (map-set locations 
               location-id 
               {
                 name: validated-name,
                 latitude: validated-latitude,
                 longitude: validated-longitude,
                 location-type: validated-location-type,
                 active: true
               })
      (var-set next-location-id (+ location-id u1))
      (ok location-id)
    )
  )
)

;; Validate water quality parameters
(define-private (is-valid-water-quality-params
                 (ph-level uint)
                 (dissolved-oxygen uint)
                 (turbidity uint)
                 (temperature uint)
                 (conductivity uint)
                 (total-dissolved-solids uint))
  (and
    (and (>= ph-level u0) (<= ph-level u1400))  ;; pH from 0 to 14.00
    (>= dissolved-oxygen u0)
    (>= turbidity u0)
    (and (>= temperature u0) (<= temperature u10000))  ;; 0 to 100.00 Celsius
    (>= conductivity u0)
    (>= total-dissolved-solids u0)
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
    ;; Check authorization
    (asserts! (is-authorized-provider tx-sender) (err ERR-UNAUTHORIZED))
    
    ;; Validate inputs
    (asserts! (is-valid-location-id location-id) (err ERR-NOT-FOUND))
    (asserts! (is-valid-timestamp timestamp) (err ERR-INVALID-DATA))
    (asserts! (is-valid-water-quality-params 
               ph-level dissolved-oxygen turbidity 
               temperature conductivity total-dissolved-solids) 
              (err ERR-INVALID-DATA))
    
    ;; Make sure no reading exists for this location and timestamp yet
    (asserts! (is-none (map-get? water-quality-readings 
                       {location-id: location-id, timestamp: timestamp}))
              (err ERR-INVALID-DATA))
    
    ;; Use validated inputs
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
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                 (is-admin tx-sender)) 
              (err ERR-UNAUTHORIZED))
    
    ;; Validate inputs
    (asserts! (is-valid-location-id location-id) (err ERR-NOT-FOUND))
    (asserts! (is-valid-timestamp timestamp) (err ERR-INVALID-DATA))
    
    (let ((reading (map-get? water-quality-readings 
                   {location-id: location-id, timestamp: timestamp})))
      
      (asserts! (is-some reading) (err ERR-NOT-FOUND))
      (asserts! (not (get verified (unwrap! reading (err ERR-NOT-FOUND)))) 
                (err ERR-ALREADY-VERIFIED))
      
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
    ;; Check authorization
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-UNAUTHORIZED))
    
    ;; Validate input - ensure new owner is not the current owner
    (asserts! (not (is-eq new-owner (var-get contract-owner))) (err ERR-INVALID-INPUT))
    
    ;; Basic validation for new owner 
    (asserts! (not (is-eq new-owner tx-sender)) (err ERR-INVALID-INPUT))
    
    ;; Use validated input
    (var-set contract-owner new-owner)
    (ok true)
  )
)