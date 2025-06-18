const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const compression = require('compression');

const app = express();
const server = http.createServer(app);

// Configure CORS and Socket.IO
const io = socketIo(server, {
  cors: {
    origin: "*", // In production, specify your app's origin
    methods: ["GET", "POST"]
  },
  transports: ['websocket'],
  pingTimeout: 30000,
  pingInterval: 10000,
});

// Middleware
app.use(compression());
app.use(cors());
app.use(express.json());

// Enhanced state management
const rooms = new Map();
const userSockets = new Map();
const activeCallInvitations = new Map();
const callTimeouts = new Map();
const userStates = new Map(); // Track user busy state

// Configuration
const CALL_TIMEOUT_DURATION = 45000; // 45 seconds
const CALL_RING_DURATION = 30000; // 30 seconds

// Logging utility
function log(level, message, data = {}) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${level.toUpperCase()}] ${message}`, 
    Object.keys(data).length > 0 ? JSON.stringify(data, null, 2) : '');
}

// Room management utilities
function createRoom(roomId, callerId, participantIds, isVideo, isGroup) {
  const room = {
    id: roomId,
    callerId,
    participantIds,
    connectedParticipants: new Set([callerId]),
    isVideo,
    isGroup,
    state: 'waiting', // waiting, active, ended
    createdAt: new Date(),
    webrtcReady: new Set(), // Track which users have WebRTC ready
  };
  
  rooms.set(roomId, room);
  log('info', 'Room created', { roomId, callerId, participantCount: participantIds.length });
  return room;
}

function cleanupRoom(roomId, reason = 'unknown') {
  const room = rooms.get(roomId);
  if (room) {
    log('info', 'Cleaning up room', { roomId, reason, duration: new Date() - room.createdAt });
    rooms.delete(roomId);
  }
  
  if (activeCallInvitations.has(roomId)) {
    activeCallInvitations.delete(roomId);
  }
  
  if (callTimeouts.has(roomId)) {
    clearTimeout(callTimeouts.get(roomId));
    callTimeouts.delete(roomId);
  }
}

function isUserBusy(userId) {
  const userState = userStates.get(userId);
  return userState?.inCall === true;
}

function setUserBusy(userId, busy = true) {
  if (!userStates.has(userId)) {
    userStates.set(userId, {});
  }
  userStates.get(userId).inCall = busy;
  log('debug', 'User busy state changed', { userId, busy });
}

// Health check endpoints
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    stats: {
      activeRooms: rooms.size,
      connectedUsers: userSockets.size,
      activeCallInvitations: activeCallInvitations.size,
      activeCallTimeouts: callTimeouts.size,
      busyUsers: Array.from(userStates.entries()).filter(([_, state]) => state.inCall).length,
    },
    memory: process.memoryUsage(),
    uptime: process.uptime(),
  });
});

app.get('/debug/rooms', (req, res) => {
  const roomsArray = Array.from(rooms.entries()).map(([id, room]) => ({
    id,
    callerId: room.callerId,
    participantCount: room.participantIds.length,
    connectedCount: room.connectedParticipants.size,
    state: room.state,
    duration: new Date() - room.createdAt,
    webrtcReadyCount: room.webrtcReady.size,
  }));
  res.json({ rooms: roomsArray });
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  log('info', 'User connected', { socketId: socket.id });

  // Register user for incoming calls
  socket.on('register-user', (data) => {
    const { userId } = data;
    userSockets.set(userId, socket.id);
    socket.userId = userId;
    log('info', 'User registered', { userId, socketId: socket.id });
  });

  // Handle call initiation
  socket.on('initiate-call', async (data) => {
    try {
      const { callId, callerId, callerName, participantIds, isVideo, isGroup } = data;
      
      log('info', 'Call initiation started', { callId, callerId, callerName, participantIds, isVideo, isGroup });

      // Check if caller is already in a call
      if (isUserBusy(callerId)) {
        socket.emit('call-failed', { 
          callId, 
          reason: 'caller_busy',
          message: 'You are already in a call' 
        });
        return;
      }

      // Check if any participants are busy
      const busyParticipants = participantIds.filter(id => isUserBusy(id));
      if (busyParticipants.length > 0) {
        socket.emit('participant-busy', { 
          callId, 
          busyParticipants,
          message: 'One or more participants are busy' 
        });
        return;
      }

      // Create room and invitation
      const room = createRoom(callId, callerId, participantIds, isVideo, isGroup);
      
      const invitation = {
        callId,
        callerId,
        callerName,
        participantIds,
        isVideo,
        isGroup,
        status: 'pending',
        initiatedAt: new Date(),
      };
      
      activeCallInvitations.set(callId, invitation);

      // Set all participants as busy
      setUserBusy(callerId, true);
      participantIds.forEach(id => setUserBusy(id, true));

      // Send call invitation to all participants
      participantIds.forEach(participantId => {
        const participantSocketId = userSockets.get(participantId);
        if (participantSocketId) {
          io.to(participantSocketId).emit('incoming-call', {
            callId,
            callerId,
            callerName,
            isVideo,
            isGroup,
            timestamp: new Date(),
          });
          log('info', 'Call invitation sent', { callId, participantId });
        } else {
          log('warn', 'Participant not connected', { participantId });
        }
      });

      // Set call timeout
      const timeout = setTimeout(() => {
        handleCallTimeout(callId);
      }, CALL_TIMEOUT_DURATION);
      
      callTimeouts.set(callId, timeout);
      
    } catch (error) {
      log('error', 'Error initiating call', { error: error.message, data });
      socket.emit('call-failed', { 
        callId: data.callId, 
        reason: 'server_error',
        message: 'Failed to initiate call' 
      });
    }
  });

  // Handle call acceptance
  socket.on('accept-call', (data) => {
    try {
      const { callId } = data;
      const invitation = activeCallInvitations.get(callId);
      const room = rooms.get(callId);
      
      if (!invitation || !room) {
        log('warn', 'Call accept failed - invitation not found', { callId });
        return;
      }

      log('info', 'Call accepted', { callId, acceptedBy: socket.userId });

      // Update invitation status
      invitation.status = 'accepted';
      invitation.acceptedAt = new Date();

      // Update room state
      room.state = 'active';
      if (socket.userId) {
        room.connectedParticipants.add(socket.userId);
      }

      // Notify caller
      const callerSocketId = userSockets.get(invitation.callerId);
      if (callerSocketId) {
        io.to(callerSocketId).emit('call-accepted', {
          callId,
          acceptedBy: socket.userId,
          timestamp: new Date(),
        });
      }

      // Clear timeout and start WebRTC negotiation timeout
      if (callTimeouts.has(callId)) {
        clearTimeout(callTimeouts.get(callId));
        callTimeouts.delete(callId);
      }

      // Set WebRTC timeout (shorter timeout for technical issues)
      const webrtcTimeout = setTimeout(() => {
        handleCallTimeout(callId, 'webrtc_timeout');
      }, 30000); // 30 seconds for WebRTC connection
      
      callTimeouts.set(callId, webrtcTimeout);

    } catch (error) {
      log('error', 'Error accepting call', { error: error.message, callId: data.callId });
    }
  });

  // Handle call decline
  socket.on('decline-call', (data) => {
    try {
      const { callId, reason = 'declined' } = data;
      const invitation = activeCallInvitations.get(callId);
      
      if (!invitation) {
        log('warn', 'Call decline failed - invitation not found', { callId });
        return;
      }

      log('info', 'Call declined', { callId, declinedBy: socket.userId, reason });

      // Notify all participants
      const allParticipants = [invitation.callerId, ...invitation.participantIds];
      allParticipants.forEach(participantId => {
        const socketId = userSockets.get(participantId);
        if (socketId && socketId !== socket.id) {
          io.to(socketId).emit('call-rejected', {
            callId,
            reason,
            rejectedBy: socket.userId,
            timestamp: new Date(),
          });
        }
      });

      // Free up all participants
      allParticipants.forEach(id => setUserBusy(id, false));

      // Clean up
      cleanupRoom(callId, 'declined');

    } catch (error) {
      log('error', 'Error declining call', { error: error.message, callId: data.callId });
    }
  });

  // Handle call cancellation
  socket.on('cancel-call', (data) => {
    try {
      const { callId } = data;
      const invitation = activeCallInvitations.get(callId);
      
      if (!invitation) {
        log('warn', 'Call cancel failed - invitation not found', { callId });
        return;
      }

      log('info', 'Call cancelled', { callId, cancelledBy: socket.userId });

      // Notify all participants
      invitation.participantIds.forEach(participantId => {
        const socketId = userSockets.get(participantId);
        if (socketId) {
          io.to(socketId).emit('call-cancelled', {
            callId,
            timestamp: new Date(),
          });
        }
      });

      // Free up all participants
      const allParticipants = [invitation.callerId, ...invitation.participantIds];
      allParticipants.forEach(id => setUserBusy(id, false));

      // Clean up
      cleanupRoom(callId, 'cancelled');

    } catch (error) {
      log('error', 'Error cancelling call', { error: error.message, callId: data.callId });
    }
  });

  // Handle call end
  socket.on('end-call', (data) => {
    try {
      const { callId, reason = 'ended' } = data;
      const room = rooms.get(callId);
      const invitation = activeCallInvitations.get(callId);
      
      log('info', 'Call ended', { callId, endedBy: socket.userId, reason });

      // Notify all participants in the room
      if (room) {
        io.to(callId).emit('call-ended', {
          callId,
          reason,
          endedBy: socket.userId,
          timestamp: new Date(),
        });

        // Free up all participants
        const allParticipants = [room.callerId, ...room.participantIds];
        allParticipants.forEach(id => setUserBusy(id, false));
      }

      // Clean up
      cleanupRoom(callId, reason);

    } catch (error) {
      log('error', 'Error ending call', { error: error.message, callId: data.callId });
    }
  });

  // WebRTC signaling events
  socket.on('webrtc-offer', (data) => {
    try {
      const { callId, offer } = data;
      const room = rooms.get(callId);
      
      if (!room) {
        log('warn', 'WebRTC offer failed - room not found', { callId });
        return;
      }

      log('debug', 'WebRTC offer received', { callId, from: socket.userId });

      // Forward offer to other participants in the room
      socket.to(callId).emit('webrtc-offer', {
        callId,
        offer,
        from: socket.userId,
      });

    } catch (error) {
      log('error', 'Error handling WebRTC offer', { error: error.message, callId: data.callId });
    }
  });

  socket.on('webrtc-answer', (data) => {
    try {
      const { callId, answer } = data;
      const room = rooms.get(callId);
      
      if (!room) {
        log('warn', 'WebRTC answer failed - room not found', { callId });
        return;
      }

      log('debug', 'WebRTC answer received', { callId, from: socket.userId });

      // Forward answer to other participants in the room
      socket.to(callId).emit('webrtc-answer', {
        callId,
        answer,
        from: socket.userId,
      });

    } catch (error) {
      log('error', 'Error handling WebRTC answer', { error: error.message, callId: data.callId });
    }
  });

  socket.on('webrtc-ice-candidate', (data) => {
    try {
      const { callId, candidate } = data;
      const room = rooms.get(callId);
      
      if (!room) {
        log('warn', 'ICE candidate failed - room not found', { callId });
        return;
      }

      log('debug', 'ICE candidate received', { callId, from: socket.userId });

      // Forward ICE candidate to other participants in the room
      socket.to(callId).emit('webrtc-ice-candidate', {
        callId,
        candidate,
        from: socket.userId,
      });

    } catch (error) {
      log('error', 'Error handling ICE candidate', { error: error.message, callId: data.callId });
    }
  });

  // Handle user joining call room (for WebRTC)
  socket.on('join-call-room', (data) => {
    try {
      const { callId } = data;
      const room = rooms.get(callId);
      
      if (!room) {
        log('warn', 'Join room failed - room not found', { callId });
        return;
      }

      socket.join(callId);
      log('info', 'User joined call room', { callId, userId: socket.userId });

      // Check if all participants are ready to start WebRTC
      const participantSocketsInRoom = Array.from(io.sockets.adapter.rooms.get(callId) || []);
      if (participantSocketsInRoom.length >= 2) {
        // Start WebRTC negotiation
        io.to(callId).emit('start-webrtc-negotiation', {
          callId,
          participantCount: participantSocketsInRoom.length,
        });
        log('info', 'WebRTC negotiation started', { callId, participantCount: participantSocketsInRoom.length });
      }

    } catch (error) {
      log('error', 'Error joining call room', { error: error.message, callId: data.callId });
    }
  });

  // Handle disconnect
  socket.on('disconnect', () => {
    try {
      log('info', 'User disconnected', { socketId: socket.id, userId: socket.userId });

      // Clean up user from userSockets map
      if (socket.userId) {
        userSockets.delete(socket.userId);
        setUserBusy(socket.userId, false);

        // Check if user was in any active calls and clean them up
        for (const [callId, invitation] of activeCallInvitations) {
          if (invitation.callerId === socket.userId || invitation.participantIds.includes(socket.userId)) {
            log('info', 'Cleaning up call due to disconnect', { callId, userId: socket.userId });
            
            // Notify other participants
            const room = rooms.get(callId);
            if (room) {
              socket.to(callId).emit('call-ended', {
                callId,
                reason: 'participant_disconnected',
                disconnectedUser: socket.userId,
                timestamp: new Date(),
              });

              // Free up all participants
              const allParticipants = [room.callerId, ...room.participantIds];
              allParticipants.forEach(id => setUserBusy(id, false));
            }
            
            cleanupRoom(callId, 'disconnect');
          }
        }
      }

    } catch (error) {
      log('error', 'Error handling disconnect', { error: error.message, socketId: socket.id });
    }
  });
});

// Handle call timeout
function handleCallTimeout(callId, reason = 'timeout') {
  try {
    const invitation = activeCallInvitations.get(callId);
    const room = rooms.get(callId);
    
    if (!invitation && !room) {
      return; // Already cleaned up
    }

    log('info', 'Call timeout', { callId, reason });

    // Notify all participants
    io.to(callId).emit('call-timeout', {
      callId,
      reason,
      timestamp: new Date(),
    });

    // Free up all participants
    if (invitation) {
      const allParticipants = [invitation.callerId, ...invitation.participantIds];
      allParticipants.forEach(id => setUserBusy(id, false));
    } else if (room) {
      const allParticipants = [room.callerId, ...room.participantIds];
      allParticipants.forEach(id => setUserBusy(id, false));
    }

    // Clean up
    cleanupRoom(callId, reason);

  } catch (error) {
    log('error', 'Error handling call timeout', { error: error.message, callId });
  }
}

// Cleanup old data periodically
setInterval(() => {
  const now = new Date();
  const cleanupThreshold = 60 * 60 * 1000; // 1 hour

  // Clean up old rooms
  for (const [roomId, room] of rooms) {
    if (now - room.createdAt > cleanupThreshold) {
      log('info', 'Cleaning up old room', { roomId, age: now - room.createdAt });
      cleanupRoom(roomId, 'old_age');
    }
  }

  // Clean up disconnected users
  for (const [userId, socketId] of userSockets) {
    if (!io.sockets.sockets.has(socketId)) {
      log('info', 'Cleaning up disconnected user', { userId, socketId });
      userSockets.delete(userId);
      setUserBusy(userId, false);
    }
  }

}, 5 * 60 * 1000); // Run every 5 minutes

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  log('info', `Signaling server running on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  log('info', 'Received SIGTERM, shutting down gracefully');
  server.close(() => {
    log('info', 'Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  log('info', 'Received SIGINT, shutting down gracefully');
  server.close(() => {
    log('info', 'Server closed');
    process.exit(0);
  });
});
