
let redisClusterConnect = [ { port: 30001, host: '127.0.0.1' } ]
let redisConnect = 'localhost:6379'

if (process.env.TEST_REDIS_CLUSTER) {
  var redisConfig = { state: 'redis',
                      stateOptions: { useCluster: true,
                                     redisOptions: [ redisClusterConnect ] },
                      adapter: 'redis',
                      adpterOptions: redisConnect }
  var states = [ redisConfig ]
} else {
  var memoryConfig = { state: 'memory', adapter: 'memory' }
  redisConfig = { state: 'redis',
                  stateOptions: { redisOptions: redisConnect },
                  adapter: 'redis',
                  adpterOptions: redisConnect }
  states = [ memoryConfig, redisConfig ]
}

const [ user1, user2, user3 ] = [ 'user1', 'user2', 'user3' ]
const [ roomName1, roomName2 ] = [ 'room1', 'room2' ]
const host = 'ws://localhost'
const port = 8000
const namespace = '/chat-service'
const cleanupTimeout = 4000

module.exports = {
  cleanupTimeout,
  host,
  memoryConfig,
  namespace,
  port,
  redisClusterConnect,
  redisConfig,
  redisConnect,
  roomName1,
  roomName2,
  states,
  user1,
  user2,
  user3
}