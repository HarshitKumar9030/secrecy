

const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const compression = require('compression');

const app = express();
const server = http.createServer(app);

// Configure CORS for your Flutter app
const io = socketIo(server, {
  cors: {
    origin: "*", // In production, specify your app's origin
    methods: ["GET", "POST"]
  },
  // Optimize for performance
  transports: ['websocket'],
  pingTimeout: 30000,
  pingInterval: 10000,
});

// Enable compression for better performance
app.use(compression());
app.use(cors());
app.use(express.json());

// Store active rooms and participants
const rooms = new Map();
const userSockets = new Map();
const activeCallInvitations = new Map(); // Track pending call invitations
const callTimeouts = new Map(); // Track call timeouts

// Call timeout configuration (in milliseconds)
const CALL_TIMEOUT_DURATION = 45000; // 45 seconds
const CALL_RING_DURATION = 30000; // 30 seconds

// Resource monitoring
function getResourceUsage() {
  const used = process.memoryUsage();
  return {
    rss: Math.round(used.rss / 1024 / 1024 * 100) / 100, // MB
    heapTotal: Math.round(used.heapTotal / 1024 / 1024 * 100) / 100, // MB
    heapUsed: Math.round(used.heapUsed / 1024 / 1024 * 100) / 100, // MB
    external: Math.round(used.external / 1024 / 1024 * 100) / 100, // MB
    uptime: Math.round(process.uptime()), // seconds
  };
}

// Health check endpoint with resource monitoring
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    activeRooms: rooms.size,
    connectedUsers: userSockets.size,
    activeCallInvitations: activeCallInvitations.size,
    activeCallTimeouts: callTimeouts.size,
    resources: getResourceUsage(),
    server: {
      nodeVersion: process.version,
      platform: process.platform,
      arch: process.arch,
    }
  });
});

// Get active calls endpoint
app.get('/active-calls', (req, res) => {
  const activeCalls = Array.from(activeCallInvitations.entries()).map(([roomId, invitation]) => ({
    roomId,
    callerId: invitation.callerId,
    callerName: invitation.callerName,
    participantCount: invitation.participantIds.length,
    isVideo: invitation.isVideo,
    isGroup: invitation.isGroup,
    status: invitation.status,
    duration: new Date() - invitation.initiatedAt
  }));
  
  res.json({
    activeCallsCount: activeCalls.length,
    activeCalls
  });
});

// Force end call endpoint (for admin/debugging)
app.post('/force-end-call/:roomId', (req, res) => {
  const { roomId } = req.params;
  
  if (activeCallInvitations.has(roomId) || rooms.has(roomId)) {
    // Force end the call
    io.to(roomId).emit('call-ended', {
      roomId,
      reason: 'force_ended',
      timestamp: new Date()
    });
    
    // Clean up
    if (callTimeouts.has(roomId)) {
      clearTimeout(callTimeouts.get(roomId));
      callTimeouts.delete(roomId);
    }
    activeCallInvitations.delete(roomId);
    rooms.delete(roomId);
    
    res.json({ success: true, message: `Call ${roomId} force ended` });
  } else {
    res.status(404).json({ error: 'Call not found' });
  }
});

// Log resource usage every 5 minutes
setInterval(() => {
  const resources = getResourceUsage();
  console.log(`[MONITOR] Memory: ${resources.heapUsed}MB/${resources.heapTotal}MB | Users: ${userSockets.size} | Rooms: ${rooms.size} | Uptime: ${resources.uptime}s`);
}, 5 * 60 * 1000);

io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);

  // Handle user identification
  socket.on('identify', (data) => {
    const { userId, userEmail } = data;
    userSockets.set(userId, {
      socketId: socket.id,
      userEmail,
      joinedAt: new Date()
    });
    socket.userId = userId;
    console.log(`User identified: ${userId} (${userEmail})`);
  });

  // Handle joining a room
  socket.on('join-room', (data) => {
    const { roomId, userId, userName } = data;
    
    socket.join(roomId);
    
    // Initialize room if it doesn't exist
    if (!rooms.has(roomId)) {
      rooms.set(roomId, {
        participants: new Map(),
        createdAt: new Date(),
        callStarted: false
      });
    }
    
    const room = rooms.get(roomId);
    room.participants.set(userId, {
      socketId: socket.id,
      userName,
      joinedAt: new Date()
    });
    
    console.log(`User ${userId} joined room ${roomId}`);
    
    // Notify other participants
    socket.to(roomId).emit('user-joined', {
      userId,
      userName,
      participantCount: room.participants.size
    });
    
    // Send current participants to the new user
    const participantList = Array.from(room.participants.entries()).map(([id, info]) => ({
      userId: id,
      userName: info.userName
    }));
    
    socket.emit('room-participants', {
      roomId,
      participants: participantList
    });
  });
  // Handle call offer
  socket.on('offer', (data) => {
    const { roomId, offer, callerId, participantIds } = data;
    console.log(`Offer received for room ${roomId} from ${callerId}`);
    
    // Forward offer to all participants except the caller
    socket.to(roomId).emit('offer', {
      roomId,
      offer,
      callerId,
      participantIds
    });
    
    // Mark call as started
    if (rooms.has(roomId)) {
      rooms.get(roomId).callStarted = true;
    }
  });

  // Handle call initiation (new - includes video/audio type and push notifications)
  socket.on('initiate-call', (data) => {
    const { roomId, callerId, callerName, participantIds, isVideo = false, isGroup = false } = data;
    console.log(`Call initiated by ${callerId} for room ${roomId}, isVideo: ${isVideo}, isGroup: ${isGroup}`);
    
    // Store call invitation details
    const callInvitation = {
      roomId,
      callerId,
      callerName,
      participantIds,
      isVideo,
      isGroup,
      initiatedAt: new Date(),
      status: 'ringing'
    };
    
    activeCallInvitations.set(roomId, callInvitation);
    
    // Set call timeout
    const timeoutId = setTimeout(() => {
      console.log(`Call timeout for room ${roomId}`);
      
      // Notify all participants that call timed out
      io.to(roomId).emit('call-timeout', {
        roomId,
        reason: 'no_answer'
      });
      
      // Clean up
      activeCallInvitations.delete(roomId);
      callTimeouts.delete(roomId);
      
      if (rooms.has(roomId)) {
        rooms.delete(roomId);
      }
    }, CALL_TIMEOUT_DURATION);
    
    callTimeouts.set(roomId, timeoutId);
    
    // Send call invitation to participants
    participantIds.forEach(participantId => {
      const participantSocket = userSockets.get(participantId);
      
      if (participantSocket) {
        // User is online - send direct call invitation
        io.to(participantSocket.socketId).emit('incoming-call', {
          roomId,
          callerId,
          callerName,
          isVideo,
          isGroup,
          participantIds
        });
      } else {
        // User is offline - would trigger push notification in real app
        console.log(`User ${participantId} is offline, should send push notification`);
        
        // In a real implementation, you would:
        // 1. Store the call in Firebase/database
        // 2. Send push notification via FCM
        // 3. Handle the call when user opens the app
        
        // For now, emit to all sockets with this user ID (in case they reconnect)
        socket.broadcast.emit('missed-call-notification', {
          roomId,
          callerId,
          callerName,
          participantId,
          isVideo,
          isGroup,
          timestamp: new Date()
        });
      }
    });
  });

  // Handle call acceptance
  socket.on('accept-call', (data) => {
    const { roomId, userId } = data;
    console.log(`Call accepted by ${userId} for room ${roomId}`);
    
    if (activeCallInvitations.has(roomId)) {
      const invitation = activeCallInvitations.get(roomId);
      invitation.status = 'accepted';
      
      // Clear timeout
      if (callTimeouts.has(roomId)) {
        clearTimeout(callTimeouts.get(roomId));
        callTimeouts.delete(roomId);
      }
      
      // Notify all participants that call was accepted
      io.to(roomId).emit('call-accepted', {
        roomId,
        acceptedBy: userId,
        callDetails: invitation
      });
      
      // Initialize room if it doesn't exist
      if (!rooms.has(roomId)) {
        rooms.set(roomId, {
          participants: new Map(),
          createdAt: new Date(),
          callStarted: true,
          isVideo: invitation.isVideo
        });
      }
    }
  });

  // Handle call rejection/decline
  socket.on('reject-call', (data) => {
    const { roomId, userId, reason = 'declined' } = data;
    console.log(`Call rejected by ${userId} for room ${roomId}, reason: ${reason}`);
    
    if (activeCallInvitations.has(roomId)) {
      const invitation = activeCallInvitations.get(roomId);
      
      // Clear timeout
      if (callTimeouts.has(roomId)) {
        clearTimeout(callTimeouts.get(roomId));
        callTimeouts.delete(roomId);
      }
      
      // For group calls, just remove this participant
      if (invitation.isGroup && invitation.participantIds.length > 2) {
        invitation.participantIds = invitation.participantIds.filter(id => id !== userId);
        
        // Notify others that this user declined
        io.to(roomId).emit('participant-declined', {
          roomId,
          declinedBy: userId,
          reason
        });
      } else {
        // For 1:1 calls or when no participants left, end the call
        io.to(roomId).emit('call-rejected', {
          roomId,
          rejectedBy: userId,
          reason
        });
        
        // Clean up
        activeCallInvitations.delete(roomId);
        if (rooms.has(roomId)) {
          rooms.delete(roomId);
        }
      }
    }
  });

  // Handle call busy (when user is already in another call)
  socket.on('call-busy', (data) => {
    const { roomId, userId } = data;
    console.log(`User ${userId} is busy for call ${roomId}`);
    
    // Notify caller that user is busy
    io.to(roomId).emit('participant-busy', {
      roomId,
      busyUserId: userId
    });
  });

  // Handle video toggle during call
  socket.on('toggle-video', (data) => {
    const { roomId, userId, isVideoEnabled } = data;
    console.log(`User ${userId} toggled video: ${isVideoEnabled} in room ${roomId}`);
    
    // Notify other participants
    socket.to(roomId).emit('participant-video-toggle', {
      roomId,
      userId,
      isVideoEnabled
    });
  });

  // Handle audio toggle during call
  socket.on('toggle-audio', (data) => {
    const { roomId, userId, isAudioEnabled } = data;
    console.log(`User ${userId} toggled audio: ${isAudioEnabled} in room ${roomId}`);
    
    // Notify other participants
    socket.to(roomId).emit('participant-audio-toggle', {
      roomId,
      userId,
      isAudioEnabled
    });
  });

  // Handle missed call acknowledgment
  socket.on('acknowledge-missed-call', (data) => {
    const { roomId, userId } = data;
    console.log(`User ${userId} acknowledged missed call ${roomId}`);
    
    // Could store this in database for call history
  });

  // Handle call answer
  socket.on('answer', (data) => {
    const { roomId, answer } = data;
    console.log(`Answer received for room ${roomId}`);
    
    // Forward answer to the caller
    socket.to(roomId).emit('answer', {
      roomId,
      answer
    });
  });

  // Handle ICE candidates
  socket.on('ice-candidate', (data) => {
    const { roomId, candidate } = data;
    
    // Forward ICE candidate to other participants
    socket.to(roomId).emit('ice-candidate', {
      roomId,
      candidate
    });
  });
  // Handle call end
  socket.on('end-call', (data) => {
    const { roomId, endedBy, reason = 'ended' } = data;
    console.log(`Call ended for room ${roomId} by ${endedBy}, reason: ${reason}`);
    
    // Clear any pending timeouts
    if (callTimeouts.has(roomId)) {
      clearTimeout(callTimeouts.get(roomId));
      callTimeouts.delete(roomId);
    }
    
    // Notify all participants that call ended
    io.to(roomId).emit('call-ended', { 
      roomId, 
      endedBy, 
      reason,
      timestamp: new Date()
    });
    
    // Clean up
    activeCallInvitations.delete(roomId);
    if (rooms.has(roomId)) {
      rooms.delete(roomId);
    }
  });

  // Handle leaving room
  socket.on('leave-room', (data) => {
    const { roomId, userId } = data;
    
    if (rooms.has(roomId)) {
      const room = rooms.get(roomId);
      room.participants.delete(userId);
      
      console.log(`User ${userId} left room ${roomId}`);
      
      // Notify other participants
      socket.to(roomId).emit('user-left', {
        userId,
        participantCount: room.participants.size
      });
      
      // If no participants left, clean up room
      if (room.participants.size === 0) {
        rooms.delete(roomId);
        console.log(`Room ${roomId} deleted (no participants)`);
      }
    }
    
    socket.leave(roomId);
  });
  // Handle disconnect
  socket.on('disconnect', () => {
    console.log(`User disconnected: ${socket.id}`);
    
    // Clean up user from rooms and maps
    if (socket.userId) {
      userSockets.delete(socket.userId);
      
      // Check if user was in any active call invitations
      activeCallInvitations.forEach((invitation, roomId) => {
        if (invitation.callerId === socket.userId) {
          // Caller disconnected, end the call
          io.to(roomId).emit('call-ended', {
            roomId,
            endedBy: socket.userId,
            reason: 'caller_disconnected',
            timestamp: new Date()
          });
          
          // Clean up
          if (callTimeouts.has(roomId)) {
            clearTimeout(callTimeouts.get(roomId));
            callTimeouts.delete(roomId);
          }
          activeCallInvitations.delete(roomId);
          
        } else if (invitation.participantIds.includes(socket.userId)) {
          // Participant disconnected during ringing
          if (invitation.status === 'ringing') {
            invitation.participantIds = invitation.participantIds.filter(id => id !== socket.userId);
            
            // If no participants left, end call
            if (invitation.participantIds.length === 0) {
              io.to(roomId).emit('call-ended', {
                roomId,
                reason: 'no_participants',
                timestamp: new Date()
              });
              
              if (callTimeouts.has(roomId)) {
                clearTimeout(callTimeouts.get(roomId));
                callTimeouts.delete(roomId);
              }
              activeCallInvitations.delete(roomId);
            }
          }
        }
      });
      
      // Remove user from all rooms
      rooms.forEach((room, roomId) => {
        if (room.participants.has(socket.userId)) {
          room.participants.delete(socket.userId);
          
          // Notify other participants
          socket.to(roomId).emit('user-left', {
            userId: socket.userId,
            participantCount: room.participants.size,
            reason: 'disconnected'
          });
          
          // Clean up empty rooms
          if (room.participants.size === 0) {
            rooms.delete(roomId);
            console.log(`Room ${roomId} deleted (user disconnect)`);
          }
        }
      });
    }
  });

  // Handle ping for connection health
  socket.on('ping', () => {
    socket.emit('pong');
  });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`WebRTC Signaling Server running on port ${PORT}`);
  console.log(`Health check available at: http://your-vm-ip:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  server.close(() => {
    process.exit(0);
  });
});