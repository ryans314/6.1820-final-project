# Server Load Test Notes

## Bugs Found

### Disconnect race condition and poor connection error handling 

#### The Bug
When a phone disconnects, it goes through the following steps:
1. closes the websocket (at the network level) 
2. removes the reference to the websocket in ConnectionManager
3. removes the player from the list of active players

In between step 1 and 2, there is a possibility for another player to attempt to send a message to a disconnecting player. They will be able to access the websocket, but since it is in the process of closing, attempting to send a message will create an error for the sender. 

When an error occurs in the ConnectionManager (either broadcast_to_phones or send_to_phone), that error is elevated and causes the sender to disconnect as a result. 

#### Resolution
To resolve the bug:
1. Primarily, when a message fails to send due to stale websocket, catch the error and remove the reference to the websocket
2. To address the root cause, would need to remove the reference to the websocket before it begins to shut down. Possible to do for intentional shutdowns, not possible for sudden disconnects. 

Resolution 1 taken. 

### Disconnect-broadcast race condition
When a phone connects to the server, that phone initiates a broadcast to all active phones. 