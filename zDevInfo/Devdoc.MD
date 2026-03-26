# WaveSync — Realtime Map System (Dev Doc)

## 1. System Overview

Users share their location and current song.  
The backend stores and processes this data through multiple layers.  
Nearby users receive real-time updates via WebSocket.  
The frontend renders users as markers on a map.

---

## 2. Core Components

### Frontend (React Native)

- Requests GPS location from device (every 15-30 seconds)
- Requests current song from Spotify
- Sends **location_update** and **song_change** events to backend
- Maintains WebSocket connection with auth token
- Renders map markers using Google Maps SDK
- Receives broadcasts from backend and updates map in real-time

---

### Backend (Layered Architecture)

The backend is organized in **strict layers** where each layer only calls the layer directly below it:

**Layer 1: WebSocket + Auth**

- Receives WebSocket connections from frontend
- Validates JWT auth token on every message
- Routes events to Socket Server

**Layer 2: Socket Server** (1 per app)

- Socket.io server instance
- Listens on port 3000
- Manages all WebSocket connections
- Passes connections to Socket Manager

**Layer 3: Socket Manager** (Central Hub, 1 per app)

- Stores userId → socket mapping
- Routes incoming events from sockets TO Managers
- Broadcasts outgoing updates FROM Managers BACK to frontend
- Handles connection/disconnection lifecycle

**Layer 4: Managers** (Orchestration)

- AuthManager: Handles authentication flow
- UserManager: Handles user data and profile
- LocationManager: Handles location updates and broadcasts to nearby users
- SongManager: Handles song changes and broadcasts

Responsibility: Decide WHAT to do. Coordinate between Socket Manager and Services.

**Layer 5: Services** (Business Logic)

- AuthService: JWT creation, verification, password hashing
- UserService: User validation, profile operations
- LocationService: Distance calculations, geo-queries, nearby user logic
- SongService: Spotify API calls, song data handling

Responsibility: HOW to do it. Validate data, perform calculations, call Repositories.

**Layer 6: Repositories** (Database Access)

- AuthRepository: User credentials queries
- UserRepository: User profile queries
- LocationRepository: Location queries, PostGIS geo-queries
- SongRepository: Song data queries

Responsibility: WHERE to store/get data. Pure database queries only. No business logic.

**Layer 7: Database** (PostgreSQL + PostGIS)

- Stores all persistent data
- Performs geographic queries with PostGIS
- Maintains indexes for performance

---

### Socket Architecture (3-Level)

```
Level 1: Socket.io Server (1 instance)
    ↓
Level 2: Socket Manager (1 instance)
    Maintains userId → socket mapping
    Routes events TO Managers
    Broadcasts updates FROM Managers back to users
    ↓
Level 3: Individual Socket Connections (1 per user)
    Each user has exactly 1 socket connection
```

**Socket Manager Responsibilities:**

- Maintains `userId → socket` mapping
- Routes events FROM individual sockets TO Managers
- Broadcasts updates FROM Managers BACK to specific user sockets

---

### Database

Simple non-relational database storing user state as documents/records:

**User Document:**

- userId
- email
- username
- spotifyToken
- createdAt

**Location Document:**

- userId
- latitude
- longitude
- updatedAt

**Song Document:**

- userId
- spotifyTrackId
- trackName
- artistName
- albumImageUrl
- updatedAt

**Like Document:**

- userId
- songId
- createdAt

**Storage Approach:**

- Simple key-value or document store
- No relational constraints
- Each document is independent
- Quick lookups by userId
- Geographic queries handled in application layer, not database

---

### Spotify API

**Who Requests Spotify?**

Frontend is responsible for detecting song changes, NOT the backend.

**Why Frontend, Not Backend?**

- Frontend already has Spotify app open
- Frontend can read current song directly via Spotify SDK
- Backend polling Spotify for every user = rate limits exceeded
  - 1000 users × 1 poll/sec = 1000 API calls/sec
  - Spotify limit = 50 calls/sec
  - Would fail immediately
- No continuous polling needed

**Backend's Role with Spotify:**

- Backend ONLY calls Spotify API if needed for:
  - Validating song data (optional security check)
  - Enriching song metadata (artist info, album art)
- Backend does NOT continuously check or poll Spotify

**Flow:**

1. User plays song in Spotify app
2. Frontend's Spotify SDK detects song change
3. Frontend sends song_change event to backend via WebSocket
4. Backend broadcasts to nearby users (no Spotify call needed)

**External Dependency:**

- Not a system layer
- Not continuously polled
- Only called for optional validation/enrichment

---

### Maps API

- Used by frontend only
- Renders map and markers
- Not called by backend
- Frontend has direct access for map rendering

---

## 3. Core Realtime Flow

### Step 1 — Connection

Frontend establishes a WebSocket connection to backend with auth token.

Backend receives connection:

1. WebSocket + Auth validates token
2. Socket Server creates connection
3. Socket Manager stores userId → socket mapping
4. UserManager saves initial location to database

---

### Step 2 — User Update

Frontend detects location change (every 15-30 seconds) or song change.

Frontend sends:

- **location_update** event with new coordinates
- **song_change** event with new song metadata

---

### Step 3 — Backend Processing

The event flows through the backend layers:

```
Socket Manager receives event
    ↓
Routes to appropriate Manager
    ↓
Manager calls appropriate Service
    ↓
Service validates data and performs calculations
    ↓
Service calls Repository
    ↓
Repository queries Database
    ↓
Database returns result
    ↓
Response flows back up through layers
```

Example: Location Update Processing

1. Socket Manager receives location_update from alice
2. Routes to LocationManager
3. LocationManager calls LocationService
4. LocationService validates and calls LocationRepository
5. LocationRepository queries database for update and nearby users
6. Database returns nearby users list
7. Response flows back up to LocationManager

---

### Step 4 — Broadcast

Manager calls Socket Manager to broadcast to nearby users.

Socket Manager looks up sockets for nearby users and sends updates to each.

---

### Step 5 — Frontend Update

Frontend receives update message from Socket Manager.

Frontend updates application state.

Frontend re-renders map markers.

User sees nearby users' locations and songs in real-time.

---

## 4. WebSocket Communication

### Frontend is Responsible for Spotify Detection

**Critical Design Decision:**
Frontend detects song changes. Backend does NOT poll Spotify.

**Why?**

- Frontend already has Spotify app open
- Frontend can read current song directly
- Backend cannot continuously poll Spotify for all users (rate limits)
  - 1000 users × 1 poll/sec = 1000 API calls/sec
  - Spotify allows 50 calls/sec max
  - System would fail immediately
- Spotify has no WebSocket or webhook events
- No way to avoid polling if backend did it

**Frontend Flow:**

1. Spotify SDK integrated in app
2. App listens for song change events
3. On song change detected:
   - Frontend captures: trackId, trackName, artistName, albumImage
   - Frontend sends song_change event to backend
4. Backend receives and broadcasts

**Backend Flow:**

1. Receives song_change event with song data
2. Optionally validates song data (security check)
3. Stores in database
4. Broadcasts to nearby users
5. **NEVER polls Spotify for updates**

**Result:**

- Real-time song updates (no polling lag)
- No rate limit issues
- Scales to millions of users
- Clean separation: Frontend detects, Backend broadcasts

### Message Types

**Frontend → Backend:**

- location_update: User's new coordinates
- song_change: User's new song
- like_song: User liked a song
- user_profile_view: User viewed another user's profile

**Backend → Frontend:**

- user_location_update: Nearby user's location changed
- user_song_update: Nearby user's song changed
- user_joined: New user appeared nearby
- user_left: User left the area
- error: Operation failed

---

## 5. Nearby User Computation

**Input:**

- User's latitude
- User's longitude
- Search radius (default 1 mile)

**Process:**

1. LocationService receives request
2. LocationService calls LocationRepository
3. LocationRepository executes PostGIS geographic query
4. Database returns all users within the radius
5. LocationService filters and returns nearby users

**Output:**
List of nearby users with:

- userId
- username
- latitude
- longitude
- distance
- current song

---

## 6. Authentication

**Login Flow:**

1. Frontend: User signs up or logs in with email + password
2. Frontend sends credentials to backend
3. Backend validates credentials
4. Backend creates JWT token with 24-hour expiration
5. Backend returns token to frontend
6. Frontend stores token and includes in all WebSocket messages
7. Backend validates token on every WebSocket event

**Spotify OAuth Flow (Alternative):**

1. Frontend initiates Spotify OAuth
2. Backend receives callback code
3. Backend exchanges code for Spotify access token
4. Backend creates/updates user record
5. Backend returns JWT token
6. Frontend stores and uses JWT (not Spotify token)

---

## 7. Update Strategy

### Location Updates

- Frequency: Every 15-30 seconds (configurable)
- Why: Balances real-time feel with battery and server load
- Alternative: Distance-based triggering (only send if moved 50+ meters)

### Song Updates

- Frequency: Immediately when song changes
- Why: Music discovery is the core feature
- Must be responsive

### Other Updates

- Likes: Immediately
- Profile views: On demand

---

## 8. Connection Lifecycle

### On Connect

1. User opens app
2. Frontend makes WebSocket connection with token
3. Backend validates token
4. Socket Manager registers user's socket
5. UserManager saves initial location to database
6. Frontend is now ready to send/receive events

### On Disconnect

1. User closes app or loses connection
2. Socket Manager detects disconnect
3. Socket Manager removes user's socket from mapping
4. Broadcasts user_left message to nearby users
5. Database may mark user as offline (optional)

### On Inactivity

- Optional: After 24 hours without activity, mark user as stale
- Optional: Auto-logout user
- User must re-login

---

## 9. System Responsibilities

### Frontend

**Collects:**

- GPS location from device
- Current song from device/Spotify
- User input (likes, shares, profile views)

**Sends:**

- Periodic location updates
- Immediate song change events
- User action events

**Displays:**

- Map with user markers
- Current location
- Nearby users' songs
- User profiles
- Connection status

**Maintains:**

- WebSocket connection
- Auth token
- Application state

---

### Backend

**Processes:**

- Incoming WebSocket events
- Authentication and authorization
- Location updates
- Song changes

**Maintains:**

- Active socket connections via Socket Manager
- User state in database
- Token validity

**Determines:**

- Which users are nearby
- Who receives broadcasts
- When to invalidate data

**Broadcasts:**

- Location updates to nearby users
- Song changes to nearby users
- User joined/left messages
- Error messages to individual users

---

### Database

**Stores:**

- User profiles
- User locations with timestamps
- Current songs with metadata
- User likes
- Authentication data

**Supports:**

- Fast geographic queries
- Concurrent updates
- Transaction safety
- Data persistence

---

### WebSocket

**Enables:**

- Two-way real-time communication
- Low-latency message delivery
- Persistent connections
- Broadcasting to multiple clients

---

## 10. System Model

- **Backend is the central coordinator**: All events route through Socket Manager and Managers
- **Database is passive storage**: Only stores, doesn't initiate actions
- **Frontend drives updates**: Only sends data when user acts or device detects change
- **WebSocket enables propagation**: Delivers updates in real-time

### The Golden Rule

**Each layer only calls the layer directly below it. No skipping.**

```
Frontend (user data entry point)
    ↓
WebSocket + Auth (transport + validation)
    ↓
Socket Server (connection management)
    ↓
Socket Manager ↔ Managers (orchestration + broadcasting)
    ↓
Services (business logic)
    ↓
Repositories (database access)
    ↓
Database (persistent storage)
```

Benefits of strict layering:

- Easy to test (mock layers below)
- Easy to debug (clear call flow)
- Easy to scale (swap implementations)
- Easy to maintain (no hidden dependencies)

---
