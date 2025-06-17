// WebRTC Signaling Server for Secrecy Chat App
// Run this on your VM with: node signaling-server.js

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
    resources: getResourceUsage(),
    server: {
      nodeVersion: process.version,
      platform: process.platform,
      arch: process.arch,
    }
  });
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
    const { roomId } = data;
    console.log(`Call ended for room ${roomId}`);
    
    // Notify all participants that call ended
    io.to(roomId).emit('call-ended', { roomId });
    
    // Clean up room
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
      
      // Remove user from all rooms
      rooms.forEach((room, roomId) => {
        if (room.participants.has(socket.userId)) {
          room.participants.delete(socket.userId);
          
          // Notify other participants
          socket.to(roomId).emit('user-left', {
            userId: socket.userId,
            participantCount: room.participants.size
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
