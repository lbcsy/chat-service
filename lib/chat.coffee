
socketIO = require 'socket.io'
_ = require 'lodash'
async = require 'async'
check = require 'check-types'
MemoryState = require('./state-memory.coffee').MemoryState
RedisState = require('./state-redis.coffee').RedisState
ErrorBuilder = require('./errors.coffee').ErrorBuilder
withEH = require('./errors.coffee').withEH
withErrorLog = require('./errors.coffee').withErrorLog


# @note This class describes socket.io outgoing messages, not methods.
#
# List of server messages that are sent to a client.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (username) ->
#     socket.on 'directMessage', (fromUser, msg) ->
#       # just the same as any event. no reply required.
#
class ServerMessages
  # Direct message.
  # @param fromUser [String] Message sender.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessage : (fromUser, msg) ->
  # Direct message echo. If an user have several connections from
  # different clients, and if one client sends
  # {UserCommands#directMessage}, others will receive a message
  # echo.
  # @param toUser [String] Message receiver
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessageEcho : (toUser, msg) ->
  # Disconnected from a server.
  disconnect : () ->
  # Indicates a successful login.
  # @param username [String]
  # @param data [Object]
  loginConfirmed : (username, data) ->
  # Indicates a login error.
  # @param error [Object] Error.
  loginRejected : (error) ->
  # Indicates that the user has lost an access permission.
  # @param roomName [String] Room name.
  roomAccessRemoved : (roomName) ->
  # Echoes room join from other user's connections.
  # @see UserCommands#roomJoin
  roomJoinedEcho : (roomName) ->
  # Echoes room leave from other user's connections.
  # @see UserCommands#roomLeave
  roomLeftEcho : (roomName) ->
  # Room message.
  # @param roomName [String] Rooms name.
  # @param userName [String] Message author.
  # @param msg Object<textMessage:String, timestamp:Number, author:String>]
  #   Message
  # @see UserCommands#roomMessage
  roomMessage : (roomName, userName, msg) ->
  # Indicates that an another user has joined a room.
  # @param roomName [String] Rooms name.
  # @param userName [String] Username.
  # @see UserCommands#roomJoin
  roomUserJoined : (roomName, userName) ->
  # Indicates that an another user has left a room.
  # @param roomName [String] Rooms name.
  # @param userName [String] Username.
  # @see UserCommands#roomLeave
  roomUserLeft : (roomName, userName) ->

# @private
checkMessage = (msg) ->
  r = check.map msg, { textMessage : check.string }
  if r then return Object.keys(msg).length == 1

# @private
dataChecker = (args, checkers) ->
  if args.length != checkers.length
    return [ 'wrongArgumentsCount', checkers.length, args.length ]
  for checker, idx in checkers
    unless checker args[idx]
      return [ 'badArgument', idx, args[idx] ]
  return null

# @note This class describes socket.io incoming messages, not methods.
#
# List of server messages that are sent from a client. Result is sent
# back as a socket.io ack with in the standard (error, data) callback
# parameters format. Error is ether a string or an object, depending
# on {ChatService} `useRawErrorObjects` option. See {ErrorBuilder} for
# an error object format description. Some messages will echo
# {ServerMessages} to other user's sockets or trigger sending
# {ServerMessages} to other users.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (username, authData) ->
#     socket.emit 'roomJoin', roomName, (error, data) ->
#       # this is a socket.io ack waiting callback.
#       # socket is joined the room, or an error occurred. we get here
#       # only when the server has finished message processing.
#
class UserCommands
  # Adds usernames to user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames to add to the list.
  # @return [error, null] Sends ack: error, null.
  directAddToList : (listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  # Gets direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @return [error, Array<String>] Sends ack: error, requested list.
  directGetAccessList : (listName) ->
    dataChecker arguments, [
      check.string
    ]
  # Gets direct messaging whitelist only mode. If it is true then
  # direct messages are allowed only for users that are it the
  # whitelist. Otherwise direct messages are accepted from all
  # users, that are not in the blacklist.
  # @return [error, Boolean] Sends ack: error, whitelist only mode.
  directGetWhitelistMode : () ->
    dataChecker arguments, [
    ]
  # Sends {ServerMessages#directMessage} to an another user, if
  # {ChatService} `enableDirectMessages` option is true. Also sends
  # {ServerMessages#directMessageEcho} to other user's sockets.
  # @see ServerMessages#directMessage
  # @see ServerMessages#directMessageEcho
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage : String>] Message.
  # @return
  #   [error, Object<textMessage:String, timestamp:Number, author:String>]
  #   Sends ack: error, message.
  directMessage : (toUser, msg) ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  # Removes usernames from user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param usernames [Array<String>] User names to add to the list.
  # @return [error, null] Sends ack: error, null.
  directRemoveFromList : (listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  # Sets direct messaging whitelist only mode.
  # @see UserCommands#directGetWhitelistMode
  # @param mode [Boolean]
  # @return [error, null] Sends ack: error, null.
  directSetWhitelistMode : (mode) ->
    dataChecker arguments, [
      check.boolean
    ]
  # Disconnects from server.
  # @param reason [String] Reason.
  disconnect : (reason) ->
    dataChecker arguments, [
      check.string
    ]
  # Gets a list of public rooms on a server.
  # @return [error, Array<String>] Sends ack: error, public rooms.
  listRooms : () ->
    dataChecker arguments, [
    ]
  # Adds usernames to room's blacklist, adminlist and whitelist. Also
  # removes users that have lost an access permission in the result of an
  # operation, sending {ServerMessages#roomAccessRemoved}.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] User names to add to the list.
  # @return [error, null] Sends ack: error, null.
  # @see ServerMessages#roomAccessRemoved
  roomAddToList : (roomName, listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  # Creates a room if {ChatService} `enableRoomsManagement` option is true.
  # @param roomName [String] Rooms name.
  # @param mode [bool] Room mode.
  # @return [error, null] Sends ack: error, null.
  roomCreate : (roomName, mode) ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]
  # Deletes a room if {ChatService} `enableRoomsManagement` is true
  # and the user has an owner status. Sends
  # {ServerMessages#roomAccessRemoved} to all room users.
  # @param roomName [String] Rooms name.
  # @return [error, null] Sends ack: error, null.
  roomDelete : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # Gets room messaging userlist, blacklist, adminlist and whitelist.
  # @param roomName [String] Room name.
  # @param listName [String] 'userlist', 'blacklist', 'adminlist', 'whitelist'.
  # @return [error, Array<String>] Sends ack: error, requested list.
  roomGetAccessList : (roomName, listName) ->
    dataChecker arguments, [
      check.string
      check.string
    ]
  # Gets a room messaging whitelist only mode. If it is true, then
  # join is allowed only for users that are in the
  # whitelist. Otherwise all users that are not in the blacklist can
  # join.
  # @return [error, Boolean] Sends ack: error, whitelist only mode.
  roomGetWhitelistMode : () ->
    dataChecker arguments, [
      check.string
    ]
  # Gets latest room messages.
  # @param roomName [String] Room name.
  # @return [error, Array<Objects>] Sends ack: error, array of messages.
  # @see UserCommands#roomMessage
  roomHistory : (roomName)->
    dataChecker arguments, [
      check.string
    ]
  # Joins room, an user must join the room to receive messages or
  # execute room commands. Sends {ServerMessages#roomJoinedEcho} to other
  # user's sockets. Also sends {ServerMessages#roomUserJoined} to other
  # room users if {ChatService} `enableUserlistUpdates` option is
  # true.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomUserJoined
  # @param roomName [String] Room name.
  # @return [error, null] Sends ack: error, null.
  roomJoin : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # Leaves room. Sends {ServerMessages#roomLeftEcho} to other user's
  # sockets. Also sends {ServerMessages#roomUserLeft} to other room
  # users if {ChatService} `enableUserlistUpdates` option is true.
  # @see ServerMessages#roomLeftEcho
  # @see ServerMessages#roomUserLeft
  # @param roomName [String] Room name.
  # @return [error, null] Sends ack: error, null.
  roomLeave : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # Sends {ServerMessages#roomMessage} to a room.
  # @see ServerMessages#roomMessage
  # @param roomName [String] Room name.
  # @param msg [Object<textMessage : String>] Message.
  # @return
  #   [error, Object<textMessage:String, timestamp:Number, author:String>]
  #   Sends ack: error, message.
  roomMessage : (roomName, msg) ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  # Removes usernames from room's blacklist, adminlist and
  # whitelist. Also removes users that have lost an access permission in
  # the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames to remove from the list.
  # @return [error, null] Sends ack: error, null.
  # @see ServerMessages#roomAccessRemoved
  roomRemoveFromList : (roomName, listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  # Sets room messaging whitelist only mode. Also removes users that
  # have lost an access permission in the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}.
  # @see UserCommands#roomGetWhitelistMode
  # @see ServerMessages#roomAccessRemoved
  # @param roomName [String] Room name.
  # @param mode [Boolean]
  # @return [error, null] Sends ack: error, null.
  roomSetWhitelistMode : (roomName, mode) ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]

# @private
userCommands = new UserCommands

# @private
serverMessages = new ServerMessages

# @private
asyncLimit = 16

# @private
processMessage = (author, msg) ->
  r = {}
  r.textMessage = msg?.textMessage?.toString() || ''
  r.timestamp = new Date().getTime()
  r.author = author
  return r


# Implements room messaging with permissions checking.
class Room

  # @param server [object] ChatService object
  # @param name [string] Room name
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.roomState
    @roomState = new state @server, @name, @server.historyMaxMessages

  # Resets room state according to the object.
  # @param state [object]
  # @param cb [callback]
  initState : (state, cb) ->
    @roomState.initState state, cb

  # @private
  isAdmin : (userName, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      @roomState.hasInList 'adminlist', userName, withEH cb, (hasName) ->
        if owner == userName or hasName
          return cb null, true
        cb null, false

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) =>
        if admin
          return cb null, false
        if listName == 'whitelist'
          @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) ->
            cb null, whitelistOnly
        else
          cb null, false

  # @private
  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) ->
      unless hasUser
        return cb null, false
      if listName == 'blacklist'
        return cb null, true
      cb null, false

  # @private
  getModeChangedCurrentAccess : (value, cb) ->
    unless value
      process.nextTick -> cb null, false
    else
      @roomState.getCommonUsers cb

  # @private
  checkList : (author, listName, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      cb()

  # @private
  checkListChange : (author, listName, name, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.ownerGet withEH cb, (owner) =>
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if name == owner
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', name, withEH cb, (hasName) =>
          if hasName
            return cb @errorBuilder.makeError 'notAllowed'
          @roomState.hasInList 'adminlist', author, withEH cb, (hasAuthor) =>
            unless hasAuthor
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  # @private
  checkListAdd : (author, listName, name, cb) ->
    @checkListChange author, listName, name, withEH cb, =>
      @roomState.hasInList listName, name, withEH cb, (hasName) =>
        if hasName
          return cb @errorBuilder.makeError 'nameInList', name, listName
        cb()

  # @private
  checkListRemove : (author, listName, name, cb) ->
    @checkListChange author, listName, name, withEH cb, =>
      @roomState.hasInList listName, name, withEH cb, (hasName) =>
        unless hasName
          return cb @errorBuilder.makeError 'noNameInList', name, listName
        cb()

  # @private
  checkModeChange : (author, value, cb) ->
    @isAdmin author, withEH cb, (admin) =>
      unless admin
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @private
  checkAcess : (userName, cb) ->
    @isAdmin userName, withEH cb, (admin) =>
      if admin
        return cb()
      @roomState.hasInList 'blacklist', userName, withEH cb, (inBlacklist) =>
        if inBlacklist
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) =>
          @roomState.hasInList 'whitelist', userName
          , withEH cb, (inWhitelist) =>
            if whitelistOnly and not inWhitelist
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  # @private
  checkIsOwner : (author, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      unless owner == author
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @private
  leave : (userName, cb) ->
    @roomState.removeFromList 'userlist', [userName], cb

  # @private
  join : (userName, cb) ->
    @checkAcess userName, withEH cb, =>
      @roomState.addToList 'userlist', [userName], cb

  # @private
  message : (author, msg, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.getList listName, cb

  # @private
  getLastMessages : (author, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messagesGet cb

  # @private
  addToList : (author, listName, values, cb) ->
    async.eachLimit values, asyncLimit, (val, fn) =>
      @checkListAdd author, listName, val, fn
    , withEH cb, =>
      data = []
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @hasAddChangedCurrentAccess val, listName, withEH fn, (changed) ->
          if changed then data.push val
          fn()
      , withEH cb, =>
        @roomState.addToList listName, values, (error) ->
          cb error, data

  # @private
  removeFromList : (author, listName, values, cb) ->
    async.eachLimit values, asyncLimit, (val, fn) =>
      @checkListRemove author, listName, val, fn
    , withEH cb, =>
      data = []
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @hasRemoveChangedCurrentAccess val, listName, withEH fn, (changed) ->
          if changed then data.push val
          fn()
      , withEH cb, =>
        @roomState.removeFromList listName, values, (error) ->
          cb error, data

  # @private
  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, withEH cb, =>
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly, withEH cb, =>
        @getModeChangedCurrentAccess whitelistOnly, cb



# Implements user to user messaging with permissions checking.
# @private
class DirectMessaging

  # @param server [object] ChatService object
  # @param name [string] User name
  constructor : (@server, @username) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.directMessagingState
    @directMessagingState = new state @server, @username

  # Resets user direct messaging state according to the object.
  # @param state [object]
  # @param cb [callback]
  initState : (state, cb) ->
    @directMessagingState.initState state, cb

  # @private
  checkUser : (author, cb) ->
    if author != @username
      error = @errorBuilder.makeError 'notAllowed'
    process.nextTick -> cb error

  # @private
  checkList : (author, listName, cb) ->
    @checkUser author, withEH cb, =>
      unless @directMessagingState.hasList listName
        error = @errorBuilder.makeError 'noList', listName
      cb error

  # @private
  hasListValue : (author, listName, name, cb) ->
    @checkList author, listName, withEH cb, =>
      if name == @username
        return cb @errorBuilder.makeError 'notAllowed'
      @directMessagingState.hasInList listName, name, cb

  # @private
  checkListAdd : (author, listName, name, cb) ->
    @hasListValue author, listName, name, withEH cb, (hasName) =>
      if hasName
        return cb @errorBuilder.makeError 'nameInList', name, listName
      cb()

  # @private
  checkListRemove : (author, listName, name, cb) ->
    @hasListValue author, listName, name, withEH cb, (hasName) =>
      unless hasName
        return cb @errorBuilder.makeError 'noNameInList', name, listName
      cb()

  # @private
  checkAcess : (userName, cb) ->
    if userName == @username
      return process.nextTick -> cb @errorBuilder.makeError 'notAllowed'
    @directMessagingState.hasInList 'blacklist', userName
    , withEH cb, (blacklisted) =>
      if blacklisted
        return cb @errorBuilder.makeError 'noUserOnline'
      @directMessagingState.whitelistOnlyGet withEH cb, (whitelistOnly) =>
        @directMessagingState.hasInList 'whitelist', userName
        , withEH cb, (hasWhitelist) =>
          if whitelistOnly and not hasWhitelist
            return cb @errorBuilder.makeError 'notAllowed'
          cb()

  # @private
  message : (author, msg, cb) ->
    @checkAcess author, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @directMessagingState.getList listName, cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @checkListAdd author, listName, val, fn
      , withEH cb, =>
        @directMessagingState.addToList listName, values, cb

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @checkListRemove author, listName, val, fn
      , withEH cb, =>
        @directMessagingState.removeFromList listName, values, cb

  # @private
  getMode : (author, cb) ->
    @checkUser author, withEH cb, =>
      @directMessagingState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkUser author, withEH cb, =>
      m = if mode then true else false
      @directMessagingState.whitelistOnlySet m, cb


# Implements socket.io messages to function calls association.
class User extends DirectMessaging

  # @param server [object] ChatService object
  # @param name [string] User name
  constructor : (@server, @username) ->
    super @server, @username
    @chatState = @server.chatState
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    state = @server.chatState.userState
    @userState = new state @server, @username

  # Resets user direct messaging state according to the object.
  # @param state [object]
  # @param cb [callback]
  initState : (state, cb) ->
    super state, cb

  # @private
  registerSocket : (socket, cb) ->
    @userState.socketAdd socket.id, withEH cb, =>
      for cmd of userCommands
        @bindCommand socket, cmd, @[cmd]
      cb null, @

  # @private
  wrapCommand : (name, fn) ->
    bname = name + 'Before'
    aname = name + 'After'
    cmd = (oargs..., cb, id) =>
      hooks = @server.hooks
      errorBuilder = @server.errorBuilder
      validator = @server.userCommands[name]
      beforeHook = hooks?[bname]
      afterHook = hooks?[aname]
      execCommand = (error, data, nargs...) =>
        if error or data then return cb error, data
        args = if nargs?.length then nargs else oargs
        argsAfter = args
        if args.length != oargs.length
          argsAfter = args.slice()
          args.length = oargs.length
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data) ->
            cb nerror, ndata
          if afterHook
            afterHook @, error, data, argsAfter, reportResults, id
          else
            reportResults()
        fn.apply @
        , [ args...
          , afterCommand
          , id ]
      process.nextTick =>
        checkerError = validator oargs...
        if checkerError
          error = errorBuilder.makeError checkerError...
          return cb error
        unless beforeHook
          execCommand()
        else
          beforeHook @, oargs..., execCommand, id
    return cmd

  # @private
  bindCommand : (socket, name, fn) ->
    cmd = @wrapCommand name, fn
    socket.on name, () ->
      cb = _.last arguments
      if typeof cb == 'function'
        args = Array.prototype.slice.call arguments, 0, -1
      else
        cb = null
        args = arguments
      ack = (error, data) ->
        error = null unless error
        data = null unless data
        cb error, data if cb
      cmd args..., ack, socket.id

  # @private
  withRoom : (roomName, fn) ->
    @chatState.getRoom roomName, fn

  # @private
  send : (id, args...) ->
    @server.nsp.in(id).emit args...

  # @private
  sendAccessRemoved : (userNames, roomName, cb) ->
    async.eachLimit userNames, asyncLimit
    , (userName, fn) =>
      @chatState.getOnlineUser userName, withEH fn, (user) =>
        user.userState.roomRemove roomName, withEH fn, =>
          user.userState.socketsGetAll withEH fn, (sockets) =>
            for id in sockets
              @send id, 'roomAccessRemoved', roomName
            fn()
    , cb

  # @private
  sendAllRoomsLeave : (cb) ->
    @userState.roomsGetAll withEH cb, (rooms) =>
      async.eachLimit rooms, asyncLimit
      , (roomName, fn) =>
        @chatState.getRoom roomName, withErrorLog @errorBuilder, (room) =>
          unless room then return fn()
          room.leave @username, withErrorLog @errorBuilder, =>
            if @enableUserlistUpdates
              @send roomName, 'roomUserLeft', roomName, @username
            fn()
       , =>
        @chatState.logoutUser @username, cb

  # @private
  reportRoomConnections : (error, id, sid, roomName, msgName, cb) ->
    if error
      @errorBuilder.handleServerError error
      error = @errorBuilder.makeError serverError, '500'
    if sid == id
      cb error
    else unless error
      @send sid, msgName, roomName

  # @private
  removeUser : (cb) ->
    @userState.socketsGetAll withEH cb, (sockets) =>
      async.eachLimit sockets, asyncLimit
      , (sid, fn) =>
        if @server.io.sockets.connected[sid]
          @server.io.sockets.connected[sid].disconnect(true)
          @sendAllRoomsLeave fn
        else
          # TODO all adapter sockets proper disconnection
          @send sid, 'disconnect'
          @server.nsp.adapter.delAll sid, => @sendAllRoomsLeave fn
      , cb

  # @private
  directAddToList : (listName, values, cb) ->
    @addToList @username, listName, values, cb

  # @private
  directGetAccessList : (listName, cb) ->
    @getList @username, listName, cb

  # @private
  directGetWhitelistMode: (cb) ->
    @getMode @username, cb

  # @private
  directMessage : (toUserName, msg, cb, id = null) ->
    unless @enableDirectMessages
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @chatState.getOnlineUser toUserName, withEH cb, (toUser) =>
      @chatState.getOnlineUser @username, withEH cb, (fromUser) =>
        msg = processMessage @username, msg
        toUser.message @username, msg, withEH cb, =>
          fromUser.userState.socketsGetAll withEH cb, (sockets) =>
            for sid in sockets
              if sid != id
                @send sid, 'directMessageEcho', toUserName, msg
            toUser.userState.socketsGetAll withEH cb, (sockets) =>
              for sid in sockets
                @send sid, 'directMessage', @username, msg
              cb null, msg

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, cb

  # @private
  disconnect : (reason, cb, id) ->
    # TODO lock user state
    @userState.socketRemove id, withEH cb, =>
      @userState.socketsGetAll withEH cb, (sockets) =>
        nsockets = sockets.lenght
        if nsockets > 0 then return cb()
        @sendAllRoomsLeave cb

  # @private
  listRooms : (cb) ->
    @chatState.listRooms cb

  # @private
  roomAddToList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.addToList @username, listName, values, withEH cb, (data) =>
        @sendAccessRemoved data, roomName, cb

  # @private
  roomCreate : (roomName, whitelistOnly, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @chatState.getRoom roomName, (error, room) =>
      if room
        error = @errorBuilder.makeError 'roomExists', roomName
        return cb error
      room = new Room @server, roomName
      room.initState { owner : @username, whitelistOnly : whitelistOnly }
      , withEH cb, => @chatState.addRoom room, cb

  # @private
  roomDelete : (roomName, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @withRoom roomName, withEH cb, (room) =>
      room.checkIsOwner @username, withEH cb, =>
        @chatState.removeRoom room.name, withEH cb, =>
          room.roomState.getList 'userlist', withEH cb, (list) =>
            @sendAccessRemoved list, roomName, cb

  # @private
  roomGetAccessList : (roomName, listName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getList @username, listName, cb

  # @private
  roomGetWhitelistMode : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMode @username, cb

  # @private
  roomHistory : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getLastMessages @username, cb

  # @private
  roomJoin : (roomName, cb, id = null) ->
    @withRoom roomName, withEH cb, (room) =>
      room.join @username, withEH cb, =>
        @userState.roomAdd roomName, withEH cb, =>
          if @enableUserlistUpdates
            @send roomName, 'roomUserJoined', roomName, @username
          # TODO lock user sockets
          @userState.socketsGetAll withEH cb, (sockets) =>
            async.eachLimit sockets, asyncLimit, (sid, fn) =>
              @server.nsp.adapter.add sid, roomName
              , (error) =>
                @reportRoomConnections error, id, sid, roomName
                , 'roomJoinedEcho', cb
                fn()

  # @private
  roomLeave : (roomName, cb, id = null) ->
    @withRoom roomName, withEH cb, (room) =>
      room.leave @username, withEH cb, =>
        @userState.roomRemove roomName, withEH cb, =>
          if @enableUserlistUpdates
            @send roomName, 'roomUserLeft', roomName, @username
          # TODO lock user sockets
          @userState.socketsGetAll withEH cb, (sockets) =>
            async.eachLimit sockets, asyncLimit, (sid, fn) =>
              @server.nsp.adapter.del sid, roomName
              , (error) =>
                @reportRoomConnections error, id, sid, roomName
                , 'roomLeftEcho', cb
                fn()

  # @private
  roomMessage : (roomName, msg, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      msg = processMessage @username, msg
      room.message @username, msg, withEH cb, =>
        @send roomName, 'roomMessage', roomName, @username, msg
        cb null, msg

  # @private
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @username, listName, values, withEH cb, (data) =>
        @sendAccessRemoved data, roomName, cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @username, mode, withEH cb, (data) =>
        @sendAccessRemoved data, roomName, cb


# An instance creates a new chat service.
class ChatService
  # Server creation/integration.
  # @option options [String] namespace
  #   io namespace, default is '/chat-service'.
  # @option options [Integer] historyMaxMessages
  #   room history size, default is 100.
  # @option options [Boolean] useRawErrorObjects
  #   Send error objects instead of strings, default is false.
  # @option options [Boolean] enableUserlistUpdates
  #   Enables {ServerMessages#roomUserJoined} and
  #   {ServerMessages#roomUserLeft} messages, default is false.
  # @option options [Boolean] enableDirectMessages
  #   Enables user to user {UserCommands#directMessage}, default is false.
  # @option options [Boolean] serverOptions
  #   Options that are passes to socket.io if server creation is required.
  # @option options [Object] io
  #   Socket.io instance that should be user by ChatService.
  # @option options [Object] http
  #   Use socket.io http server integration.
  # @option hooks [Function] auth Socket.io auth hook. Look in the
  #   socket.io documentation.
  # @option hooks
  #   [Function(<ChatService>, <Socket>, <Function(<Error>, <User>, <Object>)>)]
  #   onConnect Client connection hook. Must call a callback with
  #   either Error or an optional User and an optional 3rd argument,
  #   user state object.
  # @option hooks [Function(<ChatService, <Error>, <Function(<Error>)>)] onClose
  #   Executes when server is closed. Must call a callback.
  # @option hooks [Function(<ChatService, <Function(<Error>)>)] onStart
  #   Executes when server is started. Must call a callback.
  # @param options [Object] Options.
  # @param hooks [Object] Hooks.
  # @param state [String or Constructor] Chat state.
  constructor : (@options = {}, @hooks = {}, @state = 'memory') ->
    @setOptions()
    @setServer()
    if @hooks.onStart
      @hooks.onStart @, (error) =>
        if error then return @close null, error
        @setEvents()
    else
      @setEvents()

  # @private
  setOptions : ->
    @namespace = @options.namespace || '/chat-service'
    @historyMaxMessages = @options.historyMaxMessages || 100
    @useRawErrorObjects = @options.useRawErrorObjects || false
    @enableUserlistUpdates = @options.enableUserlistUpdates || false
    @enableRoomsManagement = @options.enableRoomsManagement || false
    @enableDirectMessages = @options.enableDirectMessages || false
    @serverOptions = @options.serverOptions

  # @private
  setServer : ->
    @io = @options.io
    @sharedIO = true if @io
    @http = @options.http unless @io
    state = switch @state
      when 'memory' then MemoryState
      when 'redis' then RedisState
      when typeof @state == 'function' then @state
      else throw new Error "Invalid state: #{@state}"
    unless @io
      if @http
        @io = socketIO @http, @serverOptions
      else
        port = @serverOptions?.port || 8000
        @io = socketIO port, @serverOptions
    @nsp = @io.of @namespace
    @userCommands = userCommands
    @serverMessages = serverMessages
    @User = (args...) =>
      new User @, args...
    @Room = (args...) =>
      new Room @, args...
    @errorBuilder = new ErrorBuilder @useRawErrorObjects, @hooks.serverErrorHook
    @chatState = new state @

  # @private
  setEvents : ->
    if @hooks.auth
      @nsp.use @hooks.auth
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @hooks.onConnect @, socket, (error, userName, userState) =>
          @addClient error, socket, userName, userState
    else
      @nsp.on 'connection', (socket) =>
        @addClient null, socket

  # @private
  rejectLogin : (socket, error) ->
    socket.emit 'loginRejected', error
    socket.disconnect(true)

  # @private
  addClient : (error, socket, userName, userState) ->
    if error then return @rejectLogin socket, error
    unless userName
      userName = socket.handshake.query?.user
      unless userName
        error = @errorBuilder.makeError 'noLogin'
        return @rejectLogin socket, error
    @chatState.loginUser userName, socket, (error, user) ->
      if error then return @rejectLogin socket, error
      fn = -> socket.emit 'loginConfirmed', userName, {}
      if userState then user.initState userState, fn
      else fn()

  # Closes server.
  # @param done [callback] Optional callback
  # @param error [object] Optional error vallue for done callback
  close : (done, error) ->
    # TODO unbind and disconnect sockets.
    cb = (error) =>
      unless @sharedIO or @http then @io.close()
      if done then process.nextTick -> done error
    if @hooks.onClose
      @hooks.onClose @, error, cb
    else
      cb()


module.exports = {
  ChatService
  User
  Room
}
