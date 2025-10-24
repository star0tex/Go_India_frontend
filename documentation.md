# Go India Frontend Documentation

## Services

### Socket Service (socket_service.dart)

A singleton service that manages WebSocket connections for real-time communication.

Key Functions:
- `connect()`: Establishes WebSocket connection with server
- `connectCustomer()`: Registers customer using MongoDB ID
- `emitCustomerRequestTripByType()`: Sends trip requests based on type (short/parcel/long)
- `onTripAccepted()`: Handles accepted trip events
- `onDriverLiveLocation()`: Tracks driver's real-time location
- `onRideConfirmed()`: Handles ride confirmation events

### Firebase Auth Service (firebase_auth_service.dart)

Manages Firebase authentication for the app.

Key Functions:
- `sendOtp()`: Sends OTP for phone verification
- `verifyOtp()`: Verifies OTP and completes authentication

## Screens

### Driver En Route Page (driver_en_route_page.dart)

Shows real-time driver tracking when a ride is ongoing.

Key Features:
- Live driver location tracking on map
- Route visualization
- Driver details card
- Trip status updates
- Distance and ETA calculations

Key Functions:
- `_updateMarkers()`: Updates driver and destination markers
- `_drawPolyline()`: Draws route on map
- `_updateDriverDistance()`: Calculates distance and ETA

### Login Page (login_page.dart)

Handles user authentication and profile verification.

Key Features:
- Phone number authentication
- OTP verification
- Profile completion check
- Navigation to appropriate screen based on profile status

### Profile Page (profile_page.dart)

Manages user profile information.

Key Features:
- User details display and editing
- Profile picture management
- Personal information updates

### Short Trip Page (short_trip_page.dart)

Handles booking flow for short distance trips.

Key Features:
- Location selection
- Vehicle type selection
- Fare calculation
- Driver matching
- Real-time trip status

Key Functions:
- `_fetchNearbyDrivers()`: Gets available drivers
- `_drawRoute()`: Shows route on map
- `_fetchFares()`: Calculates trip fares
- `_confirmRide()`: Initiates ride booking

### Real Home Page (real_home_page.dart)

Main dashboard after login.

Key Features:
- Service type selection (Auto, Bike, Parcel, etc.)
- Current location detection
- Recent locations history
- Quick booking options

Key Functions:
- `_navigateToShortTrip()`: Initiates short trip booking
- `_geocodeAndNavigate()`: Handles location search and navigation
- `_getCurrentLocation()`: Updates user's current location

## Common Features

1. Real-time Location Tracking
   - Uses Google Maps integration
   - Live driver location updates
   - Route visualization

2. Authentication Flow
   - Phone number verification
   - OTP validation
   - Profile management

3. Booking System
   - Multiple vehicle types
   - Dynamic fare calculation
   - Driver matching
   - Trip status tracking

4. Location Services
   - Current location detection
   - Location search and geocoding
   - Location history management

5. Socket Communication
   - Real-time updates
   - Trip status synchronization
   - Driver location tracking