
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
_ = require 'lodash'


# @private
# @nodoc
asyncLimit = 32

# @private
# @nodoc
nameChecker = /^[^\u0000-\u001F:{}\u007F]+$/


# @private
# @nodoc
extend = (c, mixins...) ->
  for mixin in mixins
    for name, method of mixin
      unless c::[name]
        c::[name] = method

# @private
# @nodoc
checkNameSymbols = (name) ->
  if (_.isString(name) and nameChecker.test(name))
    Promise.resolve()
  else
    Promise.reject new ChatServiceError 'invalidName', name

module.exports = {
  asyncLimit
  checkNameSymbols
  extend
  nameChecker
}
