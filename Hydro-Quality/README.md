# Water Quality Monitoring Smart Contract

This smart contract enables the secure monitoring, recording, and verification of water quality data collected from various sensors and testing facilities. Built on the Stacks blockchain using Clarity, it provides a transparent and tamper-proof system for water quality management.

## Overview

The Water Quality Monitoring Smart Contract allows authorized providers to submit water quality readings from various locations, which can then be verified by administrators. The contract maintains water quality standards and provides functions to check if water at specific locations meets safety criteria.

## Features

- **Data Collection**: Record water quality parameters including pH level, dissolved oxygen, turbidity, temperature, conductivity, and total dissolved solids
- **Location Management**: Register and track monitoring locations with geographic coordinates
- **Testing Facility Registry**: Maintain a database of authorized testing facilities
- **Data Verification**: Allow administrators to verify submitted water quality readings
- **Safety Standards**: Built-in checks for water safety based on established parameters
- **Access Control**: Role-based permissions with contract owner and administrator privileges

## Contract Structure

### Data Variables
- `contract-owner`: Principal who owns the contract
- `admin-list`: List of administrators with special privileges
- `next-location-id`: Counter for generating unique location IDs
- `next-facility-id`: Counter for generating unique facility IDs

### Maps
- `water-quality-readings`: Stores water quality data by location and timestamp
- `authorized-providers`: Tracks which principals can submit readings
- `testing-facilities`: Registry of testing facilities
- `locations`: Registry of monitoring locations

### Constants
- Safety standards for water quality (pH range, minimum dissolved oxygen)
- Error codes

## Functions

### Administrative Functions
- `initialize`: Initialize the contract
- `add-admin`: Add a new administrator
- `is-admin`: Check if a principal is an administrator
- `add-provider`: Authorize a new data provider
- `remove-provider`: Remove authorization from a provider
- `is-authorized-provider`: Check if a provider is authorized
- `transfer-ownership`: Transfer contract ownership to a new principal

### Facility and Location Management
- `add-testing-facility`: Register a new testing facility
- `add-location`: Add a new monitoring location
- `get-location`: Retrieve location information
- `get-facility`: Retrieve facility information

### Water Quality Data Management
- `submit-reading`: Submit a new water quality reading
- `verify-reading`: Verify a submitted reading
- `get-reading`: Retrieve a specific reading
- `is-water-safe`: Check if water at a location meets safety standards

## Data Structures

### Water Quality Reading
```
{
  ph-level: uint,              // pH * 100 (e.g., 700 = pH 7.0)
  dissolved-oxygen: uint,      // DO in mg/L * 100
  turbidity: uint,             // NTU * 100
  temperature: uint,           // Celsius * 100
  conductivity: uint,          // μS/cm
  total-dissolved-solids: uint, // TDS in mg/L
  verified: bool,
  verifier: (optional principal)
}
```

### Location
```
{
  name: (string-ascii 50),
  latitude: int,    // Latitude * 1,000,000
  longitude: int,   // Longitude * 1,000,000
  location-type: (string-ascii 20),
  active: bool
}
```

### Testing Facility
```
{
  facility-name: (string-ascii 50),
  location: (string-ascii 100),
  active: bool
}
```

## Usage Examples

### Adding a New Location
```clarity
(contract-call? .water-quality-contract add-location "River North Branch" 41500000 -87700000 "river")
```

### Submitting a Reading
```clarity
(contract-call? .water-quality-contract submit-reading u1 u1683721600 u720 u600 u150 u2100 u500 u300)
```

### Verifying a Reading
```clarity
(contract-call? .water-quality-contract verify-reading u1 u1683721600)
```

### Checking Water Safety
```clarity
(contract-call? .water-quality-contract is-water-safe u1 u1683721600)
```